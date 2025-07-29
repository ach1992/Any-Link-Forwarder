<?php
header('Content-Type: application/json');

$configPath = __DIR__ . '/config.json';
if (!file_exists($configPath)) {
    http_response_code(500);
    echo json_encode(['error' => 'Config file not found']);
    exit;
}

$config = json_decode(file_get_contents($configPath), true);
if (!$config || !isset($config['target_domain'], $config['target_port'])) {
    http_response_code(500);
    echo json_encode(['error' => 'Invalid config']);
    exit;
}

$targetDomain = $config['target_domain'];
$targetPort = $config['target_port'];

$requestUri = $_SERVER['REQUEST_URI'] ?? '/';
$targetUrl = "https://{$targetDomain}:{$targetPort}{$requestUri}";

$ch = curl_init($targetUrl);
curl
