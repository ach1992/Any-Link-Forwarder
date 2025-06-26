<?php

if (empty($_SERVER['HTTP_USER_AGENT'])) {
    http_response_code(403);
    exit("403 Forbidden");
}

$configPath = __DIR__ . '/config.json';
if (!file_exists($configPath)) {
    http_response_code(500);
    exit("Missing config.json");
}

$config = json_decode(file_get_contents($configPath), true);
$targetDomain = $config['target_domain'] ?? '';
$targetPort = $config['target_port'] ?? 443;

$isTextHTML = str_contains($_SERVER['HTTP_ACCEPT'] ?? '', 'text/html') || str_contains($_SERVER['HTTP_ACCEPT'] ?? '', '*/*');

$path = $_SERVER['REQUEST_URI'] ?? '';
$proxyPath = str_replace('/sub', '', $path);
$url = "https://$targetDomain:$targetPort$proxyPath";

$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, $url);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_HEADER, true);
curl_setopt($ch, CURLOPT_TIMEOUT, 10);
curl_setopt($ch, CURLOPT_USERAGENT, $_SERVER['HTTP_USER_AGENT']);
curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'GET');
curl_setopt($ch, CURLOPT_HTTPHEADER, $isTextHTML ? ['Accept: text/html'] : []);

$data = curl_exec($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);

if (curl_errno($ch)) {
    http_response_code(502);
    exit('cURL Error: ' . curl_error($ch));
}

curl_close($ch);

$headers = get_headers_from_curl_response($data);

if (!$isTextHTML && (empty($headers) || $code !== 200)) {
    http_response_code($code);
    exit('Error!');
}

foreach ($headers as $key => $header) {
    header("$key: $header");
}

function get_headers_from_curl_response(&$response): array {
    $headers = [];
    $header_text = substr($response, 0, strpos($response, "\r\n\r\n"));
    foreach (explode("\r\n", $header_text) as $i => $line) {
        if ($i === 0) continue;
        list($key, $value) = explode(': ', $line, 2);
        $key = strtolower($key);
        if (in_array($key, ['content-disposition', 'content-type', 'subscription-userinfo', 'profile-update-interval'])) {
            $headers[ucwords($key, '-')] = trim($value);
        }
    }
    $response = trim(substr($response, strlen($header_text)));
    return $headers;
}

echo $data;
