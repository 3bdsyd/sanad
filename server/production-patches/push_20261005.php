<?php
// Run over SSH, outside the document root. No credentials are printed.
// The production API is Laravel; this patch does not change the local Python API.
$base = '/home/u987286866/domains/admin.jobsnad.com/public_html';
$backup = '/home/u987286866/sanad-releases/push-audit-20261005';
$private = '/home/u987286866/sanad-private';
$credentials = $private . '/firebase-snd.json';
if (!is_dir($backup)) throw new RuntimeException('Backup directory missing');
if (!is_dir($private)) mkdir($private, 0700, true);
$source = $base . '/storage/firebase-credentials.json';
$data = json_decode(file_get_contents($source), true, flags: JSON_THROW_ON_ERROR);
if (($data['project_id'] ?? '') !== 'snd-project-8794b') throw new RuntimeException('Wrong Firebase project');
if (!file_exists($credentials)) {
    copy($source, $credentials);
    chmod($credentials, 0600);
}

$envPath = $base . '/.env';
if (!file_exists($backup . '/api.env.before')) copy($envPath, $backup . '/api.env.before');
$env = file_get_contents($envPath);
$env = preg_replace('/^\h*FIREBASE_CREDENTIALS\h*=.*$/m', '', $env);
$env .= "\nFIREBASE_CREDENTIALS=" . $credentials . "\n";
file_put_contents($envPath, $env);

// Preserve all cached production settings; only change the Firebase paths.
$cachePath = $base . '/bootstrap/cache/config.php';
if (is_file($cachePath)) {
    $config = require $cachePath;
    $default = $config['firebase']['default'];
    $config['firebase']['projects'][$default]['credentials'] = $credentials;
    $config['firebase']['credentials']['file'] = $credentials;
    file_put_contents($cachePath . '.new', '<?php return ' . var_export($config, true) . ';');
    rename($cachePath . '.new', $cachePath);
}

$controllerPath = $base . '/app/Http/Controllers/Api/AppVisitController.php';
$controller = str_replace("\r\n", "\n", file_get_contents($controllerPath));
if (!str_contains($controller, '$deviceAttributes')) {
    $start = strpos($controller, '    // نفس الجهاز');
    $end = strpos($controller, '    return response()->json(', $start);
    if ($start === false || $end === false) throw new RuntimeException('Unexpected controller structure');
    $replacement = <<<'CODE'
    // Visits without a fresh FCM token must preserve the last registered token.
    $deviceAttributes = ['platform' => $request->platform];
    if ($request->filled('fcm_token')) {
        $deviceAttributes['fcm_token'] = $request->fcm_token;
    }
    $user = User::updateOrCreate(
        ['device_id' => $request->device_id],
        $deviceAttributes
    );

    if (auth()->check()) {
        auth()->user()->update(array_merge(
            ['device_id' => $request->device_id],
            $deviceAttributes
        ));
    }

CODE;
    $controller = substr($controller, 0, $start) . $replacement . substr($controller, $end);
    file_put_contents($controllerPath . '.new', $controller);
    rename($controllerPath . '.new', $controllerPath);
}

// Explicit protection also covers stale copies remaining under storage/.
$htaccessPath = $base . '/.htaccess';
$htaccess = file_get_contents($htaccessPath);
if (!str_contains($htaccess, 'Private server credentials')) {
    $htaccess .= "\n# Private server credentials must never be served as static JSON.\n<FilesMatch \"(?i)^firebase.*\\.json$\">\n    Require all denied\n</FilesMatch>\n";
    file_put_contents($htaccessPath, $htaccess);
}
echo "Snd Firebase path and token retention patched\n";
