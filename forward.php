<?php
error_reporting(0);
ini_set('display_errors', 0);

// بارگذاری تنظیمات
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

// ساخت آدرس مقصد
$target_url = "https://{$config['target_domain']}:{$config['target_port']}{$_SERVER['REQUEST_URI']}";

// CURL برای فوروارد کامل
$ch = curl_init($target_url);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HEADER => true, // دریافت body + header
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_SSL_VERIFYPEER => false,
]);

$response = curl_exec($ch);
if ($response === false) {
    http_response_code(502);
    header("Content-Type: text/plain");
    echo "Error contacting backend: " . curl_error($ch);
    curl_close($ch);
    exit;
}

// جدا کردن هدر و بادی
$header_size = curl_getinfo($ch, CURLINFO_HEADER_SIZE);
$header = substr($response, 0, $header_size);
$body = substr($response, $header_size);
$httpcode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

// ست کردن HTTP status
http_response_code($httpcode);

// ارسال همه هدرها به جز هدرهای ممنوع (مثل Transfer-Encoding)
foreach (explode("\r\n", $header) as $line) {
    if (stripos($line, 'HTTP/') === 0 || empty($line)) continue;
    if (stripos($line, 'Transfer-Encoding:') === 0) continue;
    if (stripos($line, 'Content-Encoding:') === 0) continue; // gzip issues
    header($line, false);
}

// ارسال محتوای کامل
echo $body;
