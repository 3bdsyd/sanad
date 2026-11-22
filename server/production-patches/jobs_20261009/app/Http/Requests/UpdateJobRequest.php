<?php
namespace App\Http\Requests;

use App\Support\JobValues;
use Illuminate\Foundation\Http\FormRequest;

class UpdateJobRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    protected function prepareForValidation(): void
    {
        if ($this->header('X-Device-ID')) {
            $this->merge(['device_id' => $this->header('X-Device-ID')]);
        }
        $this->merge(JobValues::normalize($this->except('device_id')));
    }

    public function rules(): array
    {
        return ['device_id' => 'required|string|max:255']
            + JobValues::rules(partial: true)
            + ['is_active' => 'nullable|boolean'];
    }

    public function messages(): array
    {
        return JobValues::messages();
    }
}
