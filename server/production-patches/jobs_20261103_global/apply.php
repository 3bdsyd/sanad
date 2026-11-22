<?php
// Review and run manually on the Laravel host. Does not touch jobs or their status.
// php apply.php /absolute/laravel/root /absolute/new/backup/directory
$base = $argv[1] ?? '';
$backup = $argv[2] ?? '';
if (!$base || !$backup || !is_file("$base/artisan") || is_dir($backup)) {
    throw new RuntimeException('Pass the Laravel root and a NEW backup directory.');
}
// Refuse to replace production code that differs from the reviewed snapshots.
$expected = [
    'app/Support/JobValues.php' => '2bad1bd6e053f5c2b81538384c8d6f6895269ab9b3b36fb48d30ec20b3fd49e7',
    'app/Http/Controllers/Api/JobController.php' => '7cfc7204c25f68b62f1173f21ff8e20494e358510f65171cab0ab24379a1a3d0',
];
foreach ($expected as $file => $hash) {
    if (!is_file("$base/$file") || hash_file("sha256", "$base/$file") !== $hash) {
        throw new RuntimeException("Production code changed; review and merge before applying: $file");
    }
}
$copied = [
    'app/Support/JobValues.php',
    'app/Support/job_geography.json',
    'app/Support/geography-LICENSES.txt',
    'app/Http/Controllers/Api/JobController.php',
    'app/Http/Controllers/Api/JobLocationController.php',
];
$patched = ['routes/api.php'];
foreach (['create', 'edit'] as $view) {
    $path = "resources/views/dashboard/job/$view.blade.php";
    if (is_file("$base/$path")) $patched[] = $path;
}
mkdir($backup, 0700, true);
$existed = [];
foreach ([...$copied, ...$patched] as $file) {
    $existed[$file] = is_file("$base/$file");
    if ($existed[$file]) {
        @mkdir(dirname("$backup/$file"), 0700, true);
        if (!copy("$base/$file", "$backup/$file")) throw new RuntimeException("Backup failed: $file");
    }
}
file_put_contents("$backup/manifest.json", json_encode($existed, JSON_PRETTY_PRINT));

function replaceOne(string $text, string $pattern, string $replacement, string $label): string
{
    $out = preg_replace_callback($pattern, fn () => $replacement, $text, -1, $count);
    if ($out === null || $count !== 1) throw new RuntimeException("Unexpected dashboard shape: $label ($count)");
    return $out;
}

try {
    foreach ($copied as $file) {
        @mkdir(dirname("$base/$file"), 0755, true);
        if (!copy(__DIR__ . "/$file", "$base/$file")) throw new RuntimeException("Copy failed: $file");
    }
    $routes = file_get_contents("$base/routes/api.php");
    if (!str_contains($routes, 'JobLocationController')) {
        $routes .= "\n\\Illuminate\\Support\\Facades\\Route::get('job-locations', \\App\\Http\\Controllers\\Api\\JobLocationController::class);\n";
        if (file_put_contents("$base/routes/api.php", $routes) === false) throw new RuntimeException('Route write failed');
    }
    $country = <<<'BLADE'
<select name="country" required>
    @foreach(\App\Support\JobValues::countryNames() as $value)
        <option value="{{ $value }}" {{ old('country', isset($job) ? $job->country : 'سوريا') === $value ? 'selected' : '' }}>{{ $value }}</option>
    @endforeach
</select>
BLADE;
    $state = <<<'BLADE'
<input type="text" name="state" value="{{ old('state', isset($job) ? $job->state : '') }}" maxlength="100" required>
BLADE;
    foreach (array_slice($patched, 1) as $file) {
        $blade = file_get_contents("$base/$file");
        $blade = replaceOne($blade, '/<input(?=[^>]*name="country")[^>]*>/', $country, "$file country");
        $blade = replaceOne($blade, '/<select\s+name="state"[\s\S]*?<\/select>/', $state, "$file state");
        if (file_put_contents("$base/$file", $blade) === false) throw new RuntimeException("Dashboard write failed: $file");
    }
    echo "Code applied. Run php artisan optimize:clear; verify staging before release.\n";
} catch (Throwable $error) {
    foreach ($existed as $file => $exists) {
        if ($exists) copy("$backup/$file", "$base/$file");
        elseif (is_file("$base/$file")) unlink("$base/$file");
    }
    fwrite(STDERR, 'RESTORED: ' . $error->getMessage() . "\n");
    exit(1);
}
