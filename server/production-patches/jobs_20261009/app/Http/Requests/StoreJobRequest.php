<?php
namespace App\Http\Requests;

use App\Support\JobValues;
use Illuminate\Foundation\Http\FormRequest;

class StoreJobRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    protected function prepareForValidation(): void
    {
        // إدراج device_id من الـ Header تلقائياً إن وجد
        if ($this->header('X-Device-ID')) {
            $this->merge(['device_id' => $this->header('X-Device-ID')]);
        }
        // توحيد القيم مع ما يرسله التطبيق ويفلتر عليه
        $this->merge(JobValues::normalize($this->except('device_id')));
    }

    public function rules(): array
    {
        // الحالة والتفعيل لا يحددهما المعلن؛ كل إعلان جديد يبدأ قيد المراجعة.
        return ['device_id' => 'required|string|max:255'] + JobValues::rules();
    }

    public function messages(): array
    {
        return JobValues::messages();
    }
}
