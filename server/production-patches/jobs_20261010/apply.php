<?php
// Run over SSH: php apply.php [base] [backup], then php -l each touched file
// (exec() is disabled on this host). Backs up first and restores on any
// unexpected file shape.
$base = $argv[1] ?? '/home/u987286866/domains/admin.jobsnad.com/public_html';
$backup = $argv[2] ?? '/home/u987286866/sanad-releases/jobs-20261010/code-before';
$src = __DIR__ . '/app';

$copied = ['app/Http/Controllers/Api/JobController.php'];
$patched = ['app/Models/Job.php', 'app/Http/Controllers/Api/FavoriteController.php'];

if (is_dir($backup)) throw new RuntimeException("Backup already exists: $backup");
mkdir($backup, 0700, true);
foreach ([...$copied, ...$patched] as $file) {
    @mkdir(dirname("$backup/$file"), 0700, true);
    copy("$base/$file", "$backup/$file");
}

function replaceOnce(string $text, string $pattern, string $replacement, string $what): string
{
    $out = preg_replace($pattern, $replacement, $text, -1, $n);
    if ($out === null || $n !== 1) throw new RuntimeException("$what: expected 1 match, got $n");
    return $out;
}

try {
    foreach ($copied as $file) copy("$src/" . substr($file, 4), "$base/$file");

    // device_id authorizes edits and deletes; never serialize it, even in raw rows.
    $model = str_replace("\r\n", "\n", file_get_contents("$base/app/Models/Job.php"));
    $model = replaceOnce($model, '/^    use HasFactory;\n/m', "    use HasFactory;\n\n    protected \$hidden = ['device_id'];\n", 'model hidden');
    file_put_contents("$base/app/Models/Job.php", $model);

    // Favorites return each job in the same public shape as /api/jobs.
    $fav = str_replace("\r\n", "\n", file_get_contents("$base/app/Http/Controllers/Api/FavoriteController.php"));
    if (!str_contains($fav, 'use App\Http\Resources\JobResource;')) {
        $fav = replaceOnce($fav, '/^(namespace App\\\\Http\\\\Controllers\\\\Api;\n)/m', "\$1\nuse App\\Http\\Resources\\JobResource;", 'favorites use');
    }
    $fav = replaceOnce($fav, '/    public function index\(Request \$request\): JsonResponse\n    \{[\s\S]*?\n    \}\n/', <<<'PHP'
    public function index(Request $request): JsonResponse
    {
        $deviceId = $request->header('X-Device-ID') ?? $request->query('device_id');
        if (!$deviceId) {
            return response()->json(['success' => true, 'data' => []]);
        }

        $favorites = JobFavorite::where('device_id', $deviceId)
            ->with('job.jobField')
            ->latest()
            ->get();

        return response()->json([
            'success' => true,
            'data' => $favorites->map(fn ($favorite) => [
                'id' => $favorite->id,
                'job_id' => $favorite->job_id,
                'created_at' => $favorite->created_at?->toIso8601String(),
                'job' => $favorite->job ? new JobResource($favorite->job) : null,
            ]),
        ]);
    }

PHP, 'favorites index');
    file_put_contents("$base/app/Http/Controllers/Api/FavoriteController.php", $fav);
    echo "applied\n";
} catch (Throwable $e) {
    foreach ([...$copied, ...$patched] as $file) copy("$backup/$file", "$base/$file");
    fwrite(STDERR, 'RESTORED: ' . $e->getMessage() . "\n");
    exit(1);
}
