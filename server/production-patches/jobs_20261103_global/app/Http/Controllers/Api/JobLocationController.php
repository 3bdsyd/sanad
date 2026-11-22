<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Job;
use App\Support\JobValues;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class JobLocationController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $values = JobValues::normalize($request->only('country'));
        validator($values, ['country' => ['required', Rule::in(JobValues::countryNames())]])->validate();
        $country = $values['country'];
        $cities = Job::active()->where('status', 'published')->where('country', $country)
            ->whereNotNull('state')->where('state', '<>', '')
            ->distinct()->orderBy('state')->pluck('state');
        if ($country === JobValues::COUNTRY) {
            $cities = $cities->map(fn ($city) => JobValues::governorate($city) ?? $city)->unique()->values();
        }
        return response()->json(['success' => true, 'data' => ['country' => $country, 'cities' => $cities->values()]]);
    }
}
