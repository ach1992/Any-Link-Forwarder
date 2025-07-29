<?php
$configPath = __DIR__ . '/config.json';
if (!file_exists($configPath)) {
    http_response_code(500);
    echo json_encode(["error" => "Config file not found"]);
    exit;
}

$config = json_decode(file_get_contents($configPath), true);

$targetDomain = $config['target_domain'] ?? null;
$targetPort = $config['target_port'] ?? null;

if (!$targetDomain || !$targetPort) {
    http_response_code(500);
    echo json_encode(["error" => "Invalid configuration"]);
    exit;
}

// Extract token from the URL path
$requestUri = $_SERVER['REQUEST_URI'];
$token = basename($requestUri);

if (!$token || $token === 'sub') {
    http_response_code(400);
    echo json_encode(["error" => "Token not specified"]);
    exit;
}

// Construct target URL
$targetUrl = "https://{$targetDomain}:{$targetPort}/sub/{$token}";

// Forward the request
$ch = curl_init($targetUrl);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_HEADER, true);
curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false); // Optional: disable in production
curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false); // Optional: disable in production

$response = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$headerSize = curl_getinfo($ch, CURLINFO_HEADER_SIZE);
curl_close($ch);

$headers = explode("\r\n", substr($response, 0, $headerSize));
$body = substr($response, $headerSize);

// Send headers
http_response_code($httpCode);
foreach ($headers as $header) {
    if (stripos($header, 'Transfer-Encoding') !== false) continue; // Skip encoding
    if (stripos($header, 'Content-Length') !== false) continue; // Let PHP handle it
    if (stripos($header, 'Connection') !== false) continue;
    if (stripos($header, 'Content-Type') !== false) {
        header($header);
    }
}

// Send response body
echo $body;
