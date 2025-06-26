<?php
ini_set('display_errors', 1);
error_reporting(E_ALL);

$configPath = __DIR__ . '/config.json';
if (!file_exists($configPath)) {
    http_response_code(500);
    exit("❌ config.json not found.");
}

$config = json_decode(file_get_contents($configPath), true);
$targetDomain = $config['target_domain'] ?? '';
$targetPort = $config['target_port'] ?? 443;

if (empty($targetDomain)) {
    http_response_code(500);
    exit("❌ Invalid config. target_domain missing.");
}

$requestUri = $_SERVER['REQUEST_URI'] ?? '/';
if (!str_starts_with($requestUri, '/sub/')) {
    http_response_code(403);
    exit("Forbidden: Invalid path");
}

$targetUrl = "https://{$targetDomain}:{$targetPort}{$requestUri}";

$ch = curl_init();
curl_setopt_array($ch, [
    CURLOPT_URL => $targetUrl,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HEADER => true,
    CURLOPT_TIMEOUT => 10,
    CURLOPT_USERAGENT => $_SERVER['HTTP_USER_AGENT'] ?? 'forwarder',
    CURLOPT_CUSTOMREQUEST => 'GET'
]);

$response = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);

if (curl_errno($ch)) {
    http_response_code(502);
    exit("cURL Error: " . curl_error($ch));
}

curl_close($ch);

$headerSize = strpos($response, "\r\n\r\n");
$headerText = substr($response, 0, $headerSize);
$body = substr($response, $headerSize + 4);

foreach (explode("\r\n", $headerText) as $line) {
    if (stripos($line, ':') === false) continue;
    [$key, $value] = explode(':', $line, 2);
    $keyLower = strtolower($key);
    if (in_array($keyLower, ['content-type', 'subscription-userinfo', 'profile-update-interval'])) {
        header(trim($key) . ': ' . trim($value));
    }
}

echo $body;
