<?php
// Normalizes stored jobs to the app's values. Usage: php migrate.php [--apply]
// Without --apply it only prints the planned changes. Contact values are
// never printed; only counts of changed/invalid contacts.
$base = '/home/u987286866/domains/admin.jobsnad.com/public_html';
$backupFile = '/home/u987286866/sanad-releases/jobs-20261009/jobs-before.json';
require "$base/vendor/autoload.php";
$app = require "$base/bootstrap/app.php";
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
if (!class_exists(\App\Support\JobValues::class)) require __DIR__ . '/app/Support/JobValues.php';

use App\Support\JobValues;
use Illuminate\Support\Facades\DB;

$apply = in_array('--apply', $argv, true);

/** Same grouping as experienceGroup() in lib/features/jobs/domain/job.dart. */
function experienceFor(string $raw): string
{
    $value = mb_strtolower(trim($raw));
    if ($value === 'خبرة وبدون خبرة') return 'غير مطلوبة';
    if ($value === 'خبرة كبيرة حصراً') return 'خبير';
    if (in_array($value, ['بدون خبرة', 'غير مطلوبة', 'لا يشترط وجود خبرة'], true)) return 'غير مطلوبة';
    if (str_contains($value, 'يفضل') || str_contains($value, 'تفضل')) return 'يفضل الخبرة';
    if ($value === 'junior' || $value === 'entry' || str_contains($value, 'مبتدئ')) return 'مبتدئ';
    if (str_contains($value, 'متوسط')) return 'متوسطة';
    if (str_contains($value, 'خبير')) return 'خبير';
    return 'مطلوبة';
}

// Salary notes that carry information worth keeping in the description.
$uninformativePeriods = ['', 'غير محدد', 'يبدأ من'];

$rows = DB::table('jobs')->orderBy('id')->get();
if ($apply) {
    if (is_file($backupFile)) throw new RuntimeException('Backup exists; refusing to overwrite');
    file_put_contents($backupFile, json_encode($rows, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR));
    chmod($backupFile, 0600);
}

$changes = [];
$stats = ['rows' => count($rows), 'changed' => 0, 'phone_changed' => 0, 'phone_invalid' => 0, 'no_contact' => 0];
$unresolved = [];

foreach ($rows as $row) {
    $update = [];
    $notes = [];
    $hide = false;
    $normalized = JobValues::normalize([
        'country' => $row->country, 'state' => $row->state, 'job_type' => $row->job_type,
        'work_type' => $row->work_type, 'experience' => $row->experience,
        'salary_period' => $row->salary_period, 'currency' => $row->currency,
        'phone' => $row->phone, 'email' => $row->email, 'url' => $row->url,
        'requirements' => $row->requirements,
    ]);

    // State: keep the precise place in the description.
    $state = $normalized['state'];
    if (!in_array($state, JobValues::STATES, true)) {
        if ($state === 'ريموتلي' || $normalized['work_type'] === 'عن بُعد') {
            // Remote jobs without a city use دمشق, like the app's own imports.
            $state = 'دمشق';
            $normalized['work_type'] = 'عن بُعد';
        } else {
            // No governorate to file it under: hide it instead of inventing one.
            $unresolved[] = "#$row->id hidden: no governorate [$row->state]";
            $state = $row->state;
            $hide = true;
        }
    } elseif (trim((string) $row->state) !== $state) {
        // «دمشق، عدرا» starts with دمشق but the area belongs to ريف دمشق.
        if ($state === 'دمشق' && preg_match('/عدرا|جرمانا|صحنايا|قدسيا|التل|الكسوة|جديدة|دوما|حرستا|ببيلا|يبرود|النبك|الزبداني|المعضمية|داريا|السيدة زينب|الضمير|القطيفة/u', $row->state)) {
            $state = 'ريف دمشق';
        }
        $notes[] = 'العنوان: ' . trim($row->state);
    }
    $normalized['state'] = $state;

    if (!in_array($normalized['experience'], JobValues::EXPERIENCES, true)) {
        $original = trim((string) $row->experience);
        $normalized['experience'] = experienceFor($original);
        // Keep only specific experience text (e.g. a named program); generic phrases add nothing.
        $reqs = (string) ($normalized['requirements'] ?? '');
        if (mb_strlen($original) > 30 && !str_contains($reqs, $original) && !str_contains((string) $row->description, $original)) {
            $normalized['requirements'] = ltrim($reqs . "\n" . $original);
        }
    }

    if (!in_array($normalized['salary_period'], JobValues::SALARY_PERIODS, true)) {
        $original = trim((string) $row->salary_period);
        if (!in_array($original, $uninformativePeriods, true)) $notes[] = 'الراتب: ' . $original;
        $normalized['salary_period'] = 'شهرياً';
    }
    if (!in_array($normalized['currency'], JobValues::CURRENCIES, true)) {
        $unresolved[] = "#$row->id currency [$row->currency]";
    }
    foreach (['job_type' => JobValues::JOB_TYPES, 'work_type' => JobValues::WORK_TYPES] as $key => $allowed) {
        if (!in_array($normalized[$key], $allowed, true)) $unresolved[] = "#$row->id $key [{$row->$key}]";
    }

    foreach ($normalized as $key => $value) {
        if ((string) $value !== (string) $row->$key) $update[$key] = $value;
    }
    if ($notes) {
        $missing = array_filter($notes, fn ($n) => !str_contains((string) $row->description, $n));
        if ($missing) $update['description'] = rtrim((string) $row->description) . "\n\n" . implode("\n", $missing);
    }

    if (isset($update['phone'])) $stats['phone_changed']++;
    $phone = $update['phone'] ?? $row->phone;
    if ($phone !== null && $phone !== '' && !preg_match('/^\+[1-9]\d{7,14}$/', $phone)) $stats['phone_invalid']++;
    $email = $update['email'] ?? $row->email;
    $validPhone = $phone !== null && $phone !== '' && preg_match('/^\+[1-9]\d{7,14}$/', $phone);
    if (!$validPhone && ($email === null || $email === '')) {
        $stats['no_contact']++;
        $unresolved[] = "#$row->id hidden: no valid phone or email";
        $hide = true;
    }
    if ($hide && $row->is_active) $update['is_active'] = 0;

    if ($update) {
        $stats['changed']++;
        foreach ($update as $key => $value) {
            if (in_array($key, ['phone', 'email'], true)) continue;
            if ($key === 'requirements' && str_replace("\r", '', (string) $row->$key) === str_replace("\r", '', (string) $value)) { $changes['requirements: line endings / spacing only'][] = $row->id; continue; }
            $from = $key === 'description' ? '…' : (string) $row->$key;
            $to = $key === 'description' ? '…+' . implode(' | ', $notes) : (string) $value;
            $changes["$key: [$from] → [" . str_replace("\n", ' / ', $to) . ']'][] = $row->id;
        }
        if ($apply) DB::table('jobs')->where('id', $row->id)->update($update + ['updated_at' => now()]);
    }
}

ksort($changes);
foreach ($changes as $change => $ids) echo count($ids), 'x ', $change, ' ids=', implode(',', array_slice($ids, 0, 6)), count($ids) > 6 ? ',…' : '', "\n";
echo "UNRESOLVED\n", implode("\n", $unresolved), "\n";
echo json_encode($stats), $apply ? " APPLIED\n" : " DRY RUN\n";
