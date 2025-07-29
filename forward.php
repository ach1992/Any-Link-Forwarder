<?php
error_reporting(0);
ini_set('display_errors', 0);

$config_path = __DIR__ . '/config.json';
if (!file_exists($config_path)) {
    http_response_code(500);
    exit("Config file not found.");
}

$config = json_decode(file_get_contents($config_path), true);
if (!$config || !isset($config['target_domain'], $config['target_port'])) {
    http_response_code(500);
    exit("Invalid config format.");
}

$target_url = "https://{$config['target_domain']}:{$config['target_port']}{$_SERVER['REQUEST_URI']}";

$ch = curl_init($target_url);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_HEADER => true,
    CURLOPT_SSL_VERIFYPEER => false,
    CURLOPT_TIMEOUT => 15,
    CURLOPT_USERAGENT => $_SERVER['HTTP_USER_AGENT'] ?? 'Mozilla/5.0',
]);

$response = curl_exec($ch);
if ($response === false) {
    http_response_code(502);
    exit("Upstream error: " . curl_error($ch));
}

$header_size = curl_getinfo($ch, CURLINFO_HEADER_SIZE);
$header = substr($response, 0, $header_size);
$body = substr($response, $header_size);
$http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

foreach (explode("\r\n", $header) as $i => $line) {
    if ($i === 0 || trim($line) === '') continue;
    list($key, $value) = explode(': ', $line, 2);
    $key = strtolower($key);
    if (!in_array($key, ['transfer-encoding', 'content-encoding'])) {
        header("$key: $value", false);
    }
}

http_response_code($http_code);
echo $body;
