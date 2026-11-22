<?php

namespace App\Support;

use Closure;
use Illuminate\Validation\Rule;

/**
 * The only job values Sanad stores. They mirror what the Flutter app sends
 * and filters on (lib/features/jobs/domain/job.dart), so every saved job is
 * reachable through the app's filters.
 */
final class JobValues
{
    public const COUNTRY = 'سوريا';

    public const STATES = [
        'دمشق', 'ريف دمشق', 'حلب', 'حمص', 'حماة', 'اللاذقية', 'طرطوس',
        'إدلب', 'درعا', 'السويداء', 'القنيطرة', 'دير الزور', 'الرقة', 'الحسكة',
    ];

    public const JOB_TYPES = ['دوام كامل', 'دوام جزئي', 'عمل حر', 'تدريب'];

    public const WORK_TYPES = ['في المقر', 'عن بُعد', 'هجين'];

    public const EXPERIENCES = ['غير مطلوبة', 'مطلوبة', 'يفضل الخبرة', 'مبتدئ', 'متوسطة', 'خبير'];

    public const CURRENCIES = ['AED', 'AFN', 'ALL', 'AMD', 'AOA', 'ARS', 'AUD', 'AWG', 'AZN', 'BAM', 'BBD', 'BDT', 'BHD', 'BIF', 'BMD', 'BND', 'BOB', 'BRL', 'BSD', 'BTN', 'BWP', 'BYN', 'BZD', 'CAD', 'CDF', 'CHF', 'CLP', 'CNY', 'COP', 'CRC', 'CUP', 'CVE', 'CZK', 'DJF', 'DKK', 'DOP', 'DZD', 'EGP', 'ERN', 'ETB', 'EUR', 'FJD', 'FKP', 'GBP', 'GEL', 'GHS', 'GIP', 'GMD', 'GNF', 'GTQ', 'GYD', 'HKD', 'HNL', 'HTG', 'HUF', 'IDR', 'ILS', 'INR', 'IQD', 'IRR', 'ISK', 'JMD', 'JOD', 'JPY', 'KES', 'KGS', 'KHR', 'KMF', 'KPW', 'KRW', 'KWD', 'KYD', 'KZT', 'LAK', 'LBP', 'LKR', 'LRD', 'LSL', 'LYD', 'MAD', 'MDL', 'MGA', 'MKD', 'MMK', 'MNT', 'MOP', 'MRU', 'MUR', 'MVR', 'MWK', 'MXN', 'MYR', 'MZN', 'NAD', 'NGN', 'NIO', 'NOK', 'NPR', 'NZD', 'OMR', 'PAB', 'PEN', 'PGK', 'PHP', 'PKR', 'PLN', 'PYG', 'QAR', 'RON', 'RSD', 'RUB', 'RWF', 'SAR', 'SBD', 'SCR', 'SDG', 'SEK', 'SGD', 'SHP', 'SLE', 'SOS', 'SRD', 'SSP', 'STN', 'SYP', 'SZL', 'THB', 'TJS', 'TMT', 'TND', 'TOP', 'TRY', 'TTD', 'TWD', 'TZS', 'UAH', 'UGX', 'USD', 'UYU', 'UZS', 'VES', 'VND', 'VUV', 'WST', 'XAF', 'XCD', 'XCG', 'XOF', 'XPF', 'YER', 'ZAR', 'ZMW', 'ZWG'];

    public const SALARY_PERIODS = ['شهرياً', 'أسبوعياً', 'يومياً', 'بالساعة', 'للمشروع'];

    public const DURATIONS = [7, 14, 30];

    public const STATUSES = ['pending', 'published', 'rejected', 'closed'];

    /** Fields whose change sends an owner's published job back to review. */
    public const REVIEWED_FIELDS = [
        'title', 'company_name', 'country', 'state', 'job_field_id', 'job_type',
        'work_type', 'experience', 'description', 'requirements', 'url',
        'phone', 'email', 'currency', 'salary_period', 'salary_min', 'salary_max',
    ];

    private const ALIASES = [
        'job_type' => [
            'دوام كامل' => 'دوام كامل', 'دوام جزئي' => 'دوام جزئي',
            'عمل حر' => 'عمل حر', 'فريلانس' => 'عمل حر', 'تدريب' => 'تدريب',
        ],
        'work_type' => [
            'في المقر' => 'في المقر', 'من المقر' => 'في المقر',
            'في مقر العمل' => 'في المقر', 'من المكتب' => 'في المقر',
            'في المكتب' => 'في المقر', 'عن بُعد' => 'عن بُعد',
            'عن بعد' => 'عن بُعد', 'ريموتلي' => 'عن بُعد', 'هجين' => 'هجين',
        ],
        'experience' => [
            'غير مطلوبة' => 'غير مطلوبة', 'بدون خبرة' => 'غير مطلوبة',
            'لا يشترط وجود خبرة' => 'غير مطلوبة', 'لا يشترط خبرة' => 'غير مطلوبة',
            'مطلوبة' => 'مطلوبة', 'خبرة مطلوبة' => 'مطلوبة',
            'يشترط وجود خبرة' => 'مطلوبة', 'يفضل الخبرة' => 'يفضل الخبرة',
            'تُفضّل الخبرة' => 'يفضل الخبرة', 'مبتدئ' => 'مبتدئ',
            'junior' => 'مبتدئ', 'entry' => 'مبتدئ', 'متوسطة' => 'متوسطة',
            'متوسط' => 'متوسطة', 'خبرة متوسطة' => 'متوسطة', 'خبير' => 'خبير',
            'خبرة متقدمة' => 'خبير',
        ],
        'salary_period' => [
            'شهرياً' => 'شهرياً', 'شهريًا' => 'شهرياً', 'شهريا' => 'شهرياً',
            'شهري' => 'شهرياً', 'أسبوعياً' => 'أسبوعياً', 'أسبوعيًا' => 'أسبوعياً',
            'أسبوعي' => 'أسبوعياً', 'اسبوعي' => 'أسبوعياً', 'اسبوعياً' => 'أسبوعياً',
            'يومياً' => 'يومياً', 'يوميًا' => 'يومياً', 'يومي' => 'يومياً',
            'بالساعة' => 'بالساعة', 'للمشروع' => 'للمشروع',
        ],
    ];

    /** Maps known spellings to the stored values; unknown values pass through to validation. */
    public static function normalize(array $input): array
    {
        $out = [];
        foreach ($input as $key => $value) {
            if (is_string($value)) {
                $value = trim(preg_replace('/[ \t\x{00A0}]+/u', ' ', $value));
            }
            $out[$key] = match ($key) {
                'country' => self::country($value),
                'state' => self::state($value),
                'job_type', 'work_type', 'experience', 'salary_period' => self::alias($key, $value),
                'currency' => self::currency($value),
                'phone' => self::phone($value),
                'email' => $value === '' || $value === null ? null : mb_strtolower((string) $value),
                'url' => self::url($value),
                'requirements' => self::requirements($value),
                'title', 'company_name', 'description' => $value,
                'salary_min', 'salary_max' => $value === '' ? null : (is_string($value) ? self::digits($value) : $value),
                default => $value,
            };
        }
        return $out;
    }

    /** Validation rules shared by the API and the dashboard. */
    public static function rules(bool $partial = false): array
    {
        $req = $partial ? ['sometimes', 'required'] : ['required'];
        return [
            'title' => [...$req, 'string', 'min:3', 'max:100'],
            'company_name' => [...$req, 'string', 'min:2', 'max:100'],
            'country' => ['nullable', Rule::in(self::countryNames())],
            'state' => [...$req, 'string', 'min:1', 'max:100'],
            'job_field_id' => [...$req, 'integer', Rule::exists('job_fields', 'id')->where('is_active', 1)],
            'job_type' => [...$req, Rule::in(self::JOB_TYPES)],
            'work_type' => [...$req, Rule::in(self::WORK_TYPES)],
            'experience' => [...$req, Rule::in(self::EXPERIENCES)],
            'description' => [...$req, 'string', 'min:20', 'max:5000'],
            'requirements' => ['nullable', 'string', 'max:2411', self::requirementsRule()],
            'url' => ['nullable', 'string', 'max:2048', 'regex:/^https?:\/\/[^\s@\/]+\.[^\s@]+$/i'],
            'phone' => ['nullable', 'string', 'regex:/^\+[1-9]\d{7,14}$/', ...($partial ? [] : ['required_without:email'])],
            'email' => ['nullable', 'email', 'max:254', ...($partial ? [] : ['required_without:phone'])],
            'currency' => [...$req, Rule::in(self::CURRENCIES)],
            'salary_period' => [...$req, Rule::in(self::SALARY_PERIODS)],
            'salary_min' => ['nullable', 'integer', 'min:0', 'max:1000000000'],
            'salary_max' => ['nullable', 'integer', 'min:0', 'max:1000000000',
                Rule::when(fn ($input) => is_numeric($input->salary_min), ['gte:salary_min'])],
            'listing_duration_days' => [...$req, 'integer', Rule::in(self::DURATIONS)],
        ];
    }

    public static function messages(): array
    {
        return [
            'in' => 'القيمة المختارة في :attribute غير مقبولة.',
            'phone.regex' => 'رقم واتساب غير مقبول.',
            'url.regex' => 'رابط الموقع غير مقبول.',
            'salary_max.gte' => 'يجب أن يكون الحد الأعلى أكبر من الحد الأدنى أو مساوياً له.',
            'phone.required_without' => 'أدخل رقم واتساب أو بريداً إلكترونياً.',
            'email.required_without' => 'أدخل رقم واتساب أو بريداً إلكترونياً.',
        ];
    }

    /** Same rule as Job.governorateOf in the app: «دمشق، المزة» → دمشق. */
    public static function governorate(?string $place): ?string
    {
        $value = trim((string) $place);
        if (in_array($value, self::STATES, true)) return $value;
        foreach (self::STATES as $state) {
            if (str_starts_with($value, $state)
                && !preg_match('/^[\x{0621}-\x{064A}]/u', substr($value, strlen($state)))) {
                return $state;
            }
        }
        return null;
    }

    private static function alias(string $key, mixed $value): mixed
    {
        if (!is_string($value)) return $value;
        return self::ALIASES[$key][$value] ?? self::ALIASES[$key][mb_strtolower($value)] ?? $value;
    }

    private static function geography(): array
    {
        static $data;
        return $data ??= json_decode(file_get_contents(__DIR__ . '/job_geography.json'), true, 512, JSON_THROW_ON_ERROR);
    }

    public static function countryNames(): array
    {
        return array_column(self::geography()['countries'], 'name');
    }

    private static function country(mixed $value): mixed
    {
        if ($value === null || $value === '') return self::COUNTRY;
        if (!is_string($value)) return $value;
        $key = mb_strtolower(trim($value));
        foreach (self::geography()['countries'] as $country) {
            foreach ([$country['code'], $country['name'], ...$country['aliases']] as $alias) {
                if (mb_strtolower($alias) === $key) return $country['name'];
            }
        }
        return $value;
    }

    private static function state(mixed $value): mixed
    {
        return is_string($value) ? trim($value) : $value;
    }

    private static function currency(mixed $value): mixed
    {
        if (!is_string($value)) return $value;
        $named = array_search($value, self::geography()['currencies'], true);
        if ($named !== false) return $named;
        $upper = strtoupper($value);
        if (in_array($upper, self::CURRENCIES, true)) return $upper;
        if (str_contains($value, 'ليرة') || $value === 'ل.س') return 'SYP';
        if (str_contains($value, 'دولار') || $value === '$') return 'USD';
        if (str_contains($value, 'درهم')) return 'AED';
        if (str_contains($value, 'ريال')) return 'SAR';
        return $value;
    }

    private static function digits(string $value): string
    {
        return strtr($value, [
            '٠' => '0', '١' => '1', '٢' => '2', '٣' => '3', '٤' => '4',
            '٥' => '5', '٦' => '6', '٧' => '7', '٨' => '8', '٩' => '9',
            '۰' => '0', '۱' => '1', '۲' => '2', '۳' => '3', '۴' => '4',
            '۵' => '5', '۶' => '6', '۷' => '7', '۸' => '8', '۹' => '9',
        ]);
    }

    /** Same normalization as the app's post form: 09… → +9639…, 00… → +…. */
    public static function phone(mixed $value): mixed
    {
        if ($value === null || $value === '') return null;
        if (!is_string($value)) return $value;
        $text = self::digits($value);
        $plus = str_starts_with($text, '+');
        $digits = preg_replace('/\D/', '', $text);
        if ($digits === '') return $value;
        if ($plus) return '+' . $digits;
        if (str_starts_with($digits, '00')) return '+' . substr($digits, 2);
        if (str_starts_with($digits, '963')) return '+' . $digits;
        if (preg_match('/^0?9\d{8}$/', $digits)) return '+963' . ltrim($digits, '0');
        return $value;
    }

    private static function url(mixed $value): mixed
    {
        if ($value === null || $value === '') return null;
        if (!is_string($value)) return $value;
        return preg_match('/^[a-z][a-z0-9+.-]*:/i', $value) ? $value : 'https://' . $value;
    }

    private static function requirements(mixed $value): mixed
    {
        if (is_array($value)) $value = implode("\n", $value);
        if ($value === null || !is_string($value)) return $value;
        $lines = array_values(array_filter(array_map('trim', preg_split('/\R/u', $value)), fn ($l) => $l !== ''));
        return $lines ? implode("\n", $lines) : null;
    }

    private static function requirementsRule(): Closure
    {
        return function (string $attribute, mixed $value, Closure $fail) {
            $lines = preg_split('/\R/u', (string) $value);
            if (count($lines) > 12) {
                $fail('يمكن إضافة ١٢ متطلباً كحد أقصى.');
                return;
            }
            foreach ($lines as $line) {
                $length = mb_strlen($line);
                if ($length < 2 || $length > 200) {
                    $fail('طول كل متطلب بين حرفين و٢٠٠ حرف.');
                    return;
                }
            }
        };
    }
}
