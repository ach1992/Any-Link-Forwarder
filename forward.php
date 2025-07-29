<?php

header_remove('X-Powered-By');
header_remove('Connection');

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
curl_setopt($ch, CURLOPT_ENCODING, '');
curl_setopt($ch, CURLOPT_URL, $URL);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
curl_setopt($ch, CURLOPT_HEADER, true);
curl_setopt($ch, CURLOPT_TIMEOUT, 30);
curl_setopt($ch, CURLOPT_USERAGENT, $_SERVER['HTTP_USER_AGENT']);
curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'GET');

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
    if (stripos($line, 'Content-Length') === 0 || stripos($line, 'Transfer-Encoding') === 0 || stripos($line, 'Connection') === 0 || stripos($line, 'Content-Encoding') === 0 || stripos($line, 'Date') === 0 || stripos($line, 'Server') === 0) continue;
    header($line);
}

http_response_code($code);
header('Content-Length: ' . strlen($body));
echo $body;
