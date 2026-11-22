<?php
// Local checks only: no Laravel bootstrap, database, credentials or network.
require __DIR__ . '/app/Support/JobValues.php';
use App\Support\JobValues;

$catalog = json_decode(file_get_contents(__DIR__ . '/app/Support/job_geography.json'), true, 512, JSON_THROW_ON_ERROR);
$checks = 0;
foreach ($catalog['countries'] as $country) {
    foreach ([$country['code'], $country['name'], ...$country['aliases']] as $alias) {
        if (JobValues::normalize(['country' => $alias])['country'] !== $country['name']) {
            throw new RuntimeException('Country normalization mismatch: ' . $country['code']);
        }
        $checks++;
    }
}
foreach ($catalog['currencies'] as $code => $name) {
    if (!in_array($code, JobValues::CURRENCIES, true)
        || JobValues::normalize(['currency' => $code])['currency'] !== $code
        || JobValues::normalize(['currency' => $name])['currency'] !== $code) {
        throw new RuntimeException('Currency mismatch: ' . $code);
    }
    $checks++;
}
$values = JobValues::normalize(['country' => 'AE', 'state' => 'دبي، المارينا', 'currency' => 'AED', 'phone' => '+390212345678']);
if ($values['country'] !== 'الإمارات' || $values['state'] !== 'دبي، المارينا' || $values['phone'] !== '+390212345678') {
    throw new RuntimeException('Location or independent contact phone changed');
}
echo "PASS: $checks normalization checks; HTTP validation still requires Laravel staging.\n";
