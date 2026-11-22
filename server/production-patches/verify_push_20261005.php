<?php
chdir('/home/u987286866/domains/admin.jobsnad.com/public_html');
require 'vendor/autoload.php';$app=require 'bootstrap/app.php';$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$d=json_decode(file_get_contents(config('firebase.projects.'.config('firebase.default').'.credentials')),true);
if($d['project_id']!=='snd-project-8794b')throw new RuntimeException('Active project mismatch');
echo json_encode(['active_project'=>$d['project_id'],'credential_outside_web'=>!str_starts_with(realpath(config('firebase.projects.'.config('firebase.default').'.credentials')),getcwd())]).PHP_EOL;
try {
 $messaging=$app->make(Kreait\Firebase\Contract\Messaging::class);
 $message=Kreait\Firebase\Messaging\CloudMessage::withTarget('topic','sanad-config-validation')->withNotification(Kreait\Firebase\Messaging\Notification::create('Configuration validation','Validation only; no delivery'));
 $messaging->send($message,true);echo "Production container FCM validate_only: accepted\n";
}catch(Throwable $e){echo json_encode(['validation_error'=>get_class($e),'code'=>$e->getCode()]).PHP_EOL;exit(2);}
$device='sanad-audit-'.bin2hex(random_bytes(12));
Illuminate\Support\Facades\DB::beginTransaction();
try {
 $controller=new App\Http\Controllers\Api\AppVisitController();
 foreach ([['fcm_token'=>'validation-token-a'],[],['fcm_token'=>null],['fcm_token'=>'validation-token-b']] as $index=>$extra) {
  $request=Illuminate\Http\Request::create('/api/app/visit','POST',array_merge(['device_id'=>$device,'platform'=>'android'],$extra));
  $controller->store($request);
  $stored=App\Models\User::where('device_id',$device)->value('fcm_token');
  if($stored!==($index===3?'validation-token-b':'validation-token-a'))throw new RuntimeException('Token retention failed');
 }
 echo "Token registration, absent/null token retention and refresh: passed\n";
}finally{Illuminate\Support\Facades\DB::rollBack();}
echo json_encode(['audit_rows_remaining'=>App\Models\User::where('device_id',$device)->count()]).PHP_EOL;
