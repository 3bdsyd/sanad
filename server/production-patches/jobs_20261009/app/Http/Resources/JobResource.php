<?php
namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class JobResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        // device_id يخوّل تعديل الإعلان وحذفه، فلا يظهر في أي جواب.
        return [
            'id' => $this->id,
            'title' => $this->title,
            'company_name' => $this->company_name,
            'views_count' => $this->views_count,
            'url' => $this->url,
            'country' => $this->country,
            'state' => $this->state,
            'job_field' => new JobFieldResource($this->whenLoaded('jobField')),
            'job_type' => $this->job_type,
            'work_type' => $this->work_type,
            'experience' => $this->experience,
            'description' => $this->description,
            'requirements' => $this->requirements,
            'contact' => [
                'phone' => $this->phone,
                'email' => $this->email,
            ],
            'salary' => [
                'currency' => $this->currency,
                'period' => $this->salary_period,
                'min' => $this->salary_min,
                'max' => $this->salary_max,
            ],
            'listing_duration_days' => $this->listing_duration_days,
            'expires_at' => $this->expires_at?->toIso8601String(),
            'is_active' => $this->is_active,
            'status' => $this->status,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
