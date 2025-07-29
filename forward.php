<?php
error_reporting(0);
ini_set('display_errors', 0);

$config_path = __DIR__ . '/config.json';
if (!file_exists($config_path)) {
    http_response_code(500);
    header("Content-Type: text/plain");
    echo "Config file not found.";
    exit;
}

$config = json_decode(file_get_contents($config_path), true);
if (!$config || !isset($config['target_domain'], $config['target_port'])) {
    http_response_code(500);
    header("Content-Type: text/plain");
    echo "Invalid config format.";
    exit;
}

$target_domain = $config['target_domain'];
$target_port = $config['target_port'];
$request_uri = $_SERVER['REQUEST_URI'];
$target_url = "https://{$target_domain}:{$target_port}{$request_uri}";

$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, $target_url);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 10);
curl_setopt($ch, CURLOPT_TIMEOUT, 15);

$response = curl_exec($ch);
$httpcode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$content_type = curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
$curl_error = curl_error($ch);
curl_close($ch);

if ($response === false || $httpcode === 0) {
    http_response_code(502);
    header("Content-Type: text/plain");
    echo "Forwarding failed: $curl_error";
    exit;
}

http_response_code($httpcode);
if ($content_type) {
    header("Content-Type: $content_type");
} else {
    header("Content-Type: text/plain");
}

echo $response;
