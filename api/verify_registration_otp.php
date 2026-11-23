<?php

header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

if ($_SERVER["REQUEST_METHOD"] === "OPTIONS") {
    http_response_code(200);
    exit;
}

require_once "config.php";

function sendResponse($success, $message, $extra = []) {
    echo json_encode(array_merge([
        "success" => $success,
        "message" => $message
    ], $extra));
    exit;
}

// Only accept POST requests
if ($_SERVER["REQUEST_METHOD"] !== "POST") {
    http_response_code(405);
    sendResponse(false, "Invalid request method.");
}

// Get submitted values
$email = trim($_POST["email"] ?? "");
$otp = trim($_POST["otp"] ?? "");

// Validate input
if (empty($email) || empty($otp)) {
    sendResponse(false, "Email and verification code are required.");
}

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    sendResponse(false, "Invalid email address.");
}

if (!preg_match('/^[0-9]{6}$/', $otp)) {
    sendResponse(false, "Please enter a valid six-digit verification code.");
}

try {

    // Find the latest unused registration OTP for this email
    $stmt = $conn->prepare("
        SELECT id, otp_hash, attempts, expires_at, verified_at
        FROM registration_email_otps
        WHERE email = ? AND used_at IS NULL
        ORDER BY id DESC
        LIMIT 1
    ");

    $stmt->bind_param("s", $email);
    $stmt->execute();

    $result = $stmt->get_result();
    $record = $result->fetch_assoc();
    $stmt->close();

    if (!$record) {
        sendResponse(false, "No pending verification code found. Please request a new one.");
    }

    // Check expiration
    if (strtotime($record["expires_at"]) <= time()) {
        sendResponse(false, "Your verification code has expired. Please request a new one.");
    }

    // Check whether the OTP was already verified
    if (!empty($record["verified_at"])) {
        sendResponse(false, "This code has already been verified. Please request a new one if needed.");
    }

    // Limit incorrect attempts
    if ((int)$record["attempts"] >= 5) {
        sendResponse(false, "Too many incorrect attempts. Please request a new code.");
    }

    // Verify the submitted OTP against its stored hash
    if (!password_verify($otp, $record["otp_hash"])) {

        $update = $conn->prepare("
            UPDATE registration_email_otps
            SET attempts = attempts + 1
            WHERE id = ?
        ");

        $update->bind_param("i", $record["id"]);
        $update->execute();
        $update->close();

        sendResponse(false, "Incorrect verification code.");
    }

    // Generate a temporary registration token
    $registrationToken = bin2hex(random_bytes(32));

    // Store only the SHA-256 hash of the token
    $tokenHash = hash("sha256", $registrationToken);

    // Mark the OTP as verified
    $update = $conn->prepare("
        UPDATE registration_email_otps
        SET verified_at = NOW(),
            registration_token_hash = ?,
            attempts = attempts + 1
        WHERE id = ?
    ");

    $update->bind_param("si", $tokenHash, $record["id"]);
    $update->execute();
    $update->close();

    sendResponse(true, "Email verified successfully.", [
        "registrationToken" => $registrationToken
    ]);

} catch (Exception $e) {

    error_log("Registration OTP verification error: " . $e->getMessage());

    http_response_code(500);
    sendResponse(false, "Something went wrong. Please try again.");

}

?>
