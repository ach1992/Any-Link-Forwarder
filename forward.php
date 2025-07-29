<?php

if (empty($_SERVER['HTTP_USER_AGENT'])) {
    http_response_code(403);
    exit("Access Denied");
}

$accept = $_SERVER['HTTP_ACCEPT'] ?? '';
$isTextHTML = str_contains($accept, 'text/html') || str_contains($accept, '*/*');

$instancePath = __DIR__;
$configPath = $instancePath . '/config.json';

if (!file_exists($configPath)) {
    http_response_code(500);
    exit("Config file not found");
}

$config = json_decode(file_get_contents($configPath), true);
$targetDomain = $config['target_domain'];
$targetPort = $config['target_port'];

$path = $_SERVER['REQUEST_URI'] ?? '';
$proxyPath = $path; 

$portSegment = ($targetPort == 443) ? '' : ':' . $targetPort;
$URL = "https://{$targetDomain}{$portSegment}{$proxyPath}";

$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, $URL);
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

$header_text = substr($data, 0, strpos($data, "\r\n\r\n"));
$body = substr($data, strlen($header_text) + 4);

foreach (explode("\r\n", $header_text) as $i => $line) {
    if ($i === 0) continue;
    list($key, $value) = explode(': ', $line, 2);
    $key = strtolower($key);
    if (in_array($key, ['subscription-userinfo', 'profile-update-interval'])) {
        header(ucwords($key, '-') . ': ' . trim($value));
    }
}

header('Content-Type: text/plain');

http_response_code($code);
echo $body;
