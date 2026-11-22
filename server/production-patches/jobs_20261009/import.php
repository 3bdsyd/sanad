<?php
// Imports reviewed jobs from a JSON file. Usage: php import.php jobs.json [--apply]
// Each row is validated with the same rules as the API before any insert;
// one invalid row aborts the whole import. Rows are tied to a private import
// device id kept outside the web root, so they can be managed later.
$base = '/home/u987286866/domains/admin.jobsnad.com/public_html';
require "$base/vendor/autoload.php";
$app = require "$base/bootstrap/app.php";
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Models\Job;
use App\Support\JobValues;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

$file = $argv[1] ?? throw new RuntimeException('JSON file required');
$apply = in_array('--apply', $argv, true);
$rows = json_decode(file_get_contents($file), true, flags: JSON_THROW_ON_ERROR);

$deviceFile = '/home/u987286866/sanad-private/import-device-id';
if (!is_file($deviceFile) && $apply) {
    file_put_contents($deviceFile, 'sanad-import-' . bin2hex(random_bytes(24)));
    chmod($deviceFile, 0600);
}
$deviceId = is_file($deviceFile) ? trim(file_get_contents($deviceFile)) : 'dry-run';

$prepared = [];
$errors = 0;
foreach ($rows as $row) {
    $status = $row['status'] ?? 'pending';
    $data = JobValues::normalize(array_diff_key($row, array_flip(['msg', 'status', 'notes'])));
    $v = Validator::make($data, JobValues::rules(), JobValues::messages());
    if ($v->fails() || !in_array($status, ['pending', 'published'], true)) {
        $errors++;
        echo "INVALID msg {$row['msg']}: ", implode(' | ', $v->errors()->all()), "\n";
        continue;
    }
    $prepared[] = [$row['msg'], $v->validated() + ['device_id' => $deviceId, 'status' => $status, 'is_active' => true]];
}
if ($errors) {
    echo "$errors invalid rows; nothing imported\n";
    exit(1);
}

$counts = ['published' => 0, 'pending' => 0];
if ($apply) {
    DB::transaction(function () use ($prepared, &$counts) {
        foreach ($prepared as [$msg, $data]) {
            $job = Job::create($data);
            $counts[$data['status']]++;
            echo "msg $msg -> #$job->id {$data['status']}\n";
        }
    });
} else {
    foreach ($prepared as [, $data]) $counts[$data['status']]++;
}
echo json_encode($counts), $apply ? " IMPORTED\n" : " VALID (dry run)\n";
