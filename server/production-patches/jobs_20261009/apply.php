<?php
// Run over SSH from the uploaded patch folder: php apply.php, then php -l each
// touched file (exec() is disabled on this host).
// Backs up every touched file, installs the shared job values, and fails
// closed: any unexpected file shape restores the backups and stops.
$base = $argv[1] ?? '/home/u987286866/domains/admin.jobsnad.com/public_html';
$backup = $argv[2] ?? '/home/u987286866/sanad-releases/jobs-20261009/code-before';
$src = __DIR__ . '/app';

$copied = [
    'app/Support/JobValues.php',
    'app/Http/Requests/StoreJobRequest.php',
    'app/Http/Requests/UpdateJobRequest.php',
    'app/Http/Resources/JobResource.php',
    'app/Http/Controllers/Api/JobController.php',
];
$patched = [
    'app/Models/Job.php',
    'app/Http/Controllers/Dashboard/JobsController.php',
    'app/Http/Controllers/Dashboard/FilterjobsController.php',
    'resources/views/dashboard/job/create.blade.php',
    'resources/views/dashboard/job/edit.blade.php',
];

if (is_dir($backup)) throw new RuntimeException("Backup already exists: $backup");
mkdir($backup, 0700, true);
foreach ([...$copied, ...$patched] as $file) {
    if (!is_file("$base/$file")) continue;
    @mkdir(dirname("$backup/$file"), 0700, true);
    copy("$base/$file", "$backup/$file");
}

function restore(string $base, string $backup, array $files): void
{
    foreach ($files as $file) {
        if (is_file("$backup/$file")) copy("$backup/$file", "$base/$file");
        elseif (is_file("$base/$file")) unlink("$base/$file");
    }
}

function replaceOnce(string $text, string $pattern, string $replacement, string $what, int $count = 1): string
{
    $out = preg_replace($pattern, $replacement, $text, -1, $n);
    if ($out === null || $n !== $count) throw new RuntimeException("$what: expected $count match(es), got $n");
    return $out;
}

try {
    foreach ($copied as $file) {
        @mkdir(dirname("$base/$file"), 0755, true);
        copy("$src/" . substr($file, 4), "$base/$file");
    }

    // Model: every write path stores the app's values.
    $model = str_replace("\r\n", "\n", file_get_contents("$base/app/Models/Job.php"));
    $model = replaceOnce($model, '/^use Carbon\\\\Carbon;$/m', "use App\\Support\\JobValues;\nuse Carbon\\Carbon;", 'model use');
    $model = replaceOnce($model, '/protected static function booted\(\)\s*\{\n/', <<<'PHP'
protected static function booted()
    {
        // توحيد القيم مع التطبيق لكل مسارات الحفظ (API ولوحة التحكم).
        static::saving(function ($job) {
            $keys = ['country', 'state', 'job_type', 'work_type', 'experience',
                'salary_period', 'currency', 'phone', 'email', 'url', 'requirements'];
            $dirty = array_intersect_key($job->getDirty(), array_flip($keys));
            foreach (JobValues::normalize($dirty) as $key => $value) {
                $job->setAttribute($key, $value);
            }
            if (!$job->country) {
                $job->country = JobValues::COUNTRY;
            }
        });

PHP, 'model booted');
    file_put_contents("$base/app/Models/Job.php", $model);

    // Dashboard create/edit: same values and limits as the app.
    $dashRules = <<<'PHP'
$request->merge(JobValues::normalize($request->except(['_token', '_method'])));
        $validated = $request->validate(JobValues::rules() + [
            'device_id' => ['nullable', 'string', 'max:255'],
            'expires_at' => ['nullable', 'date'],
            'status' => ['required', Rule::in(JobValues::STATUSES)],
            'is_active' => ['nullable', 'boolean'],
        ], JobValues::messages());
PHP;
    $jobs = str_replace("\r\n", "\n", file_get_contents("$base/app/Http/Controllers/Dashboard/JobsController.php"));
    $jobs = replaceOnce($jobs, '/^use App\\\\Models\\\\Job;$/m', "use App\\Models\\Job;\nuse App\\Support\\JobValues;\nuse Illuminate\\Validation\\Rule;", 'jobs use');
    $jobs = replaceOnce($jobs, '/\$validated = \$request->validate\(\[[\s\S]*?\n        \]\);/', $dashRules, 'jobs validate', 2);
    file_put_contents("$base/app/Http/Controllers/Dashboard/JobsController.php", $jobs);

    $filter = str_replace("\r\n", "\n", file_get_contents("$base/app/Http/Controllers/Dashboard/FilterjobsController.php"));
    $filter = replaceOnce($filter, '/^use App\\\\Models\\\\Job;$/m', "use App\\Models\\Job;\nuse App\\Support\\JobValues;", 'filter use');
    $filter = replaceOnce($filter, '/\$validated = \$request->validate\(\[[\s\S]*?\n        \]\);/', <<<'PHP'
$request->merge(JobValues::normalize($request->except(['_token', '_method'])));
        $validated = $request->validate(JobValues::rules(partial: true) + [
            'is_active' => 'required|boolean',
        ], JobValues::messages());
PHP, 'filter validate');
    file_put_contents("$base/app/Http/Controllers/Dashboard/FilterjobsController.php", $filter);

    $select = function (string $name, string $list, string $default = "''", bool $required = true): string {
        $req = $required ? ' required' : '';
        return <<<BLADE
<select name="$name"$req>
                                <option value="">اختر</option>
                                @foreach(\\App\\Support\\JobValues::$list as \$value)
                                    <option value="{{ \$value }}" {{ (string) old('$name', isset(\$job) ? \$job->$name : $default) === (string) \$value ? 'selected' : '' }}>{{ \$value }}</option>
                                @endforeach
                            </select>
BLADE;
    };
    foreach (['create', 'edit'] as $view) {
        $path = "$base/resources/views/dashboard/job/$view.blade.php";
        $blade = str_replace("\r\n", "\n", file_get_contents($path));
        $blade = replaceOnce($blade, '/<input(?=[^>]*name="country")[^>]*>/', '<input type="text" name="country" value="سوريا" readonly>', "$view country");
        $blade = replaceOnce($blade, '/<input(?=[^>]*name="state")[^>]*>/', $select('state', 'STATES'), "$view state");
        $blade = replaceOnce($blade, '/<select\s+name="job_type"[\s\S]*?<\/select>/', $select('job_type', 'JOB_TYPES'), "$view job_type");
        $blade = replaceOnce($blade, '/<select\s+name="work_type"[\s\S]*?<\/select>/', $select('work_type', 'WORK_TYPES'), "$view work_type");
        $blade = replaceOnce($blade, '/<select\s+name="experience"[\s\S]*?<\/select>/', $select('experience', 'EXPERIENCES'), "$view experience");
        $blade = replaceOnce($blade, '/<input(?=[^>]*name="currency")[^>]*>/', $select('currency', 'CURRENCIES', "'SYP'"), "$view currency");
        $blade = replaceOnce($blade, '/<select\s+name="salary_period"[\s\S]*?<\/select>/', $select('salary_period', 'SALARY_PERIODS', "'شهرياً'"), "$view salary_period");
        $blade = replaceOnce($blade, '/<input(?=[^>]*name="listing_duration_days")[^>]*>/', $select('listing_duration_days', 'DURATIONS', '30'), "$view duration");
        file_put_contents($path, $blade);
    }

    echo "applied\n";
} catch (Throwable $e) {
    restore($base, $backup, [...$copied, ...$patched]);
    fwrite(STDERR, 'RESTORED: ' . $e->getMessage() . "\n");
    exit(1);
}
