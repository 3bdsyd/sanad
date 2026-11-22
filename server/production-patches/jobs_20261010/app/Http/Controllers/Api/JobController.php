<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\StoreJobRequest;
use App\Http\Requests\UpdateJobRequest;
use App\Http\Resources\JobResource;
use App\Models\Job;
use App\Support\JobValues;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class JobController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $query = Job::active()
            ->where('status', 'published')
            ->with('jobField')
            ->latest();

        if ($request->has('job_field_id')) {
            $query->where('job_field_id', $request->job_field_id);
        }

        if ($request->has('state')) {
            $query->where('state', $request->state);
        }

        // 30 افتراضياً، وحتى 50 عند طلب التطبيق
        $perPage = min(max((int) $request->get('per_page', 30), 1), 50);
        $jobs = $query->paginate($perPage);

        return response()->json([
            'success' => true,
            'data' => JobResource::collection($jobs),
            'meta' => [
                'current_page' => $jobs->currentPage(),
                'last_page' => $jobs->lastPage(),
                'per_page' => $jobs->perPage(),
                'total' => $jobs->total(),
                'from' => $jobs->firstItem(),
                'to' => $jobs->lastItem(),
            ]
        ]);
    }

    public function filterjob(Request $request): JsonResponse
    {
        // معايير الفلترة بنفس قيم التطبيق؛ device_id ليس فلتراً عاماً.
        $filters = JobValues::normalize($request->only([
            'search',
            'job_field_id',
            'country',
            'state',
            'job_type',
            'work_type',
            'experience',
            'currency',
            'salary_period',
            'salary_min',
            'salary_max',
        ]));

        // الحد الأدنى يطابق التطبيق: أعلى راتب معلن (أو الأدنى وحده) لا يقل عنه.
        $salaryMin = $filters['salary_min'] ?? null;
        unset($filters['salary_min']);

        $perPage = min(max((int) $request->get('per_page', 15), 1), 50);
        $sortOrder = $request->get('sort', 'latest'); // latest, oldest or salary

        $query = Job::active()
            ->where('status', 'published')
            ->with('jobField')
            ->filter($filters);

        if (is_numeric($salaryMin)) {
            $query->whereRaw('COALESCE(salary_max, salary_min) >= ?', [(int) $salaryMin]);
        }
        if ($request->boolean('has_salary')) {
            $query->where(fn ($q) => $q->whereNotNull('salary_min')->orWhereNotNull('salary_max'));
        }

        // ترتيب الراتب له معنى فقط ضمن عملة وفترة واحدتين، كما في التطبيق.
        if ($sortOrder === 'salary' && !empty($filters['currency']) && !empty($filters['salary_period'])) {
            $query->orderByRaw('COALESCE(salary_max, salary_min) DESC')->latest();
        } elseif ($sortOrder === 'oldest') {
            $query->oldest();
        } else {
            $query->latest();
        }

        $jobs = $query->paginate($perPage);

        return response()->json([
            'success' => true,
            'message' => 'تم جلب الوظائف بنجاح.',
            'data' => JobResource::collection($jobs),
            'meta' => [
                'current_page' => $jobs->currentPage(),
                'last_page'    => $jobs->lastPage(),
                'per_page'     => $jobs->perPage(),
                'total'        => $jobs->total(),
            ],
        ]);
    }

    // عرض الوظائف التي نشرها جهاز محدد فقط
    public function myJobs(Request $request): JsonResponse
    {
        $deviceId = $request->header('X-Device-ID') ?? $request->query('device_id');

        if (!$deviceId) {
            return response()->json([
                'success' => false,
                'message' => 'يرجى إرسال X-Device-ID في الهيدر أو Query String.'
            ], 400);
        }

        $jobs = Job::forDevice($deviceId)->with('jobField')->latest()->get();

        return response()->json([
            'success' => true,
            'data' => JobResource::collection($jobs),
        ]);
    }

    // إضافة وظيفة جديدة: تبدأ قيد المراجعة دائماً
    public function store(StoreJobRequest $request): JsonResponse
    {
        $job = Job::create([
            ...$request->validated(),
            'status' => 'pending',
            'is_active' => true,
        ]);

        return response()->json([
            'success' => true,
            'message' => 'تم إرسال الوظيفة للمراجعة.',
            'data' => new JobResource($job->load('jobField')),
        ], 201);
    }

    // عرض تفاصيل وظيفة: المنشورة للعامة، وغيرها لمالكها فقط
    public function show(Request $request, Job $job): JsonResponse
    {
        $public = $job->status === 'published'
            && Job::active()->whereKey($job->id)->exists();
        $deviceId = $request->header('X-Device-ID');
        $owner = $deviceId && $job->device_id && hash_equals($job->device_id, $deviceId);

        if (!$public && !$owner) {
            return response()->json([
                'success' => false,
                'message' => 'الوظيفة غير متاحة.',
            ], 404);
        }

        if ($public) {
            $job->increment('views_count');
        }

        return response()->json([
            'success' => true,
            'data' => new JobResource($job->load('jobField')),
        ]);
    }

    // تعديل وظيفة (بشرط المطابقة مع device_id)
    public function update(UpdateJobRequest $request, Job $job): JsonResponse
    {
        if (!$job->device_id || !hash_equals($job->device_id, $request->validated('device_id'))) {
            return response()->json([
                'success' => false,
                'message' => 'غير مصرح لك بتعديل هذه الوظيفة.'
            ], 403);
        }

        $data = collect($request->validated())->except('device_id')->all();
        $job->fill($data);

        // أي تعديل على المحتوى يعيد الإعلان إلى المراجعة
        if ($job->isDirty(JobValues::REVIEWED_FIELDS) && $job->status !== 'pending') {
            $job->status = 'pending';
        }

        $job->save();

        return response()->json([
            'success' => true,
            'message' => 'تم تحديث الوظيفة بنجاح.',
            'data' => new JobResource($job->load('jobField')),
        ]);
    }

    // حذف وظيفة (بشرط المطابقة مع device_id)
    public function destroy(Request $request, Job $job): JsonResponse
    {
        $deviceId = $request->header('X-Device-ID') ?? $request->input('device_id');

        if (!$deviceId || !$job->device_id || !hash_equals($job->device_id, $deviceId)) {
            return response()->json([
                'success' => false,
                'message' => 'غير مصرح لك بحذف هذه الوظيفة.'
            ], 403);
        }

        $job->delete();

        return response()->json([
            'success' => true,
            'message' => 'تم حذف الوظيفة بنجاح.',
        ]);
    }
}
