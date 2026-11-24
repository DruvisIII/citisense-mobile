<?php

header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Accept");

// Handle CORS preflight request
if ($_SERVER["REQUEST_METHOD"] === "OPTIONS") {
    http_response_code(200);
    exit;
}

require_once "config.php";
require_once __DIR__ . "/validation.php";

mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

function respond($success, $message, $extra = [], $status = 200) {
    http_response_code($status);

    echo json_encode(array_merge([
        "success" => $success,
        "message" => $message
    ], $extra));

    exit;
}

// Only allow POST requests
if ($_SERVER["REQUEST_METHOD"] !== "POST") {
    respond(false, "Invalid request method.", [], 405);
}

// Receive registration details
$firstName = trim($_POST["firstName"] ?? "");
$lastName = trim($_POST["lastName"] ?? "");
$email = strtolower(trim($_POST["email"] ?? ""));
$password = $_POST["password"] ?? "";
$contactNo = trim($_POST["contactNo"] ?? "");
$barangayID = trim($_POST["barangayID"] ?? "");
$registrationToken = trim($_POST["registrationToken"] ?? "");

// Check required fields
if (
    $firstName === "" ||
    $lastName === "" ||
    $email === "" ||
    $password === "" ||
    $contactNo === "" ||
    $barangayID === "" ||
    $registrationToken === ""
) {
    respond(false, "Please complete all required fields.");
}

// Validate email
if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    respond(false, "Invalid email address.");
}

// Validate password
$passwordError = citisense_password_error($password);
if ($passwordError !== null) {
    respond(false, $passwordError);
}

// Validate and normalize the Philippine mobile number (stored as 09XXXXXXXXX)
$normalizedContact = citisense_normalize_ph_mobile($contactNo);

if ($normalizedContact === null) {
    respond(false, CITISENSE_PHONE_ERROR);
}

$contactNo = $normalizedContact;

// Validate registration token format
if (!preg_match('/^[a-f0-9]{64}$/', $registrationToken)) {
    respond(false, "Invalid registration verification token.");
}

$tokenHash = hash("sha256", $registrationToken);

try {

    // Start database transaction
    $conn->begin_transaction();

    /*
    |--------------------------------------------------------------------------
    | Validate selected barangay
    |--------------------------------------------------------------------------
    */

    $barangayStmt = $conn->prepare("
        SELECT barangayID
        FROM barangay
        WHERE barangayID = ?
        LIMIT 1
    ");

    $barangayStmt->bind_param("s", $barangayID);
    $barangayStmt->execute();

    $barangayResult = $barangayStmt->get_result();

    if ($barangayResult->num_rows === 0) {
        $barangayStmt->close();
        $conn->rollback();

        respond(false, "Invalid barangay selection.");
    }

    $barangayStmt->close();

    /*
    |--------------------------------------------------------------------------
    | Verify registration token
    |--------------------------------------------------------------------------
    */

    $tokenStmt = $conn->prepare("
        SELECT id
        FROM registration_email_otps
        WHERE email = ?
          AND registration_token_hash = ?
          AND verified_at IS NOT NULL
          AND used_at IS NULL
          AND expires_at > NOW()
        ORDER BY id DESC
        LIMIT 1
        FOR UPDATE
    ");

    $tokenStmt->bind_param("ss", $email, $tokenHash);
    $tokenStmt->execute();

    $tokenResult = $tokenStmt->get_result();
    $tokenRecord = $tokenResult->fetch_assoc();

    $tokenStmt->close();

    if (!$tokenRecord) {
        $conn->rollback();

        respond(
            false,
            "Email verification is invalid or has expired. Please verify your email again."
        );
    }

    $otpRecordId = (int)$tokenRecord["id"];

    /*
    |--------------------------------------------------------------------------
    | Check duplicate email
    |--------------------------------------------------------------------------
    */

    $checkStmt = $conn->prepare("
        SELECT userID
        FROM users
        WHERE email = ?
        LIMIT 1
    ");

    $checkStmt->bind_param("s", $email);
    $checkStmt->execute();

    $checkResult = $checkStmt->get_result();

    if ($checkResult->num_rows > 0) {
        $checkStmt->close();
        $conn->rollback();

        respond(false, "Email is already registered.");
    }

    $checkStmt->close();

    /*
    |--------------------------------------------------------------------------
    | Generate User ID
    |--------------------------------------------------------------------------
    */

    $idResult = $conn->query("
        SELECT userID
        FROM users
        WHERE userID LIKE 'USR%'
        ORDER BY CAST(SUBSTRING(userID, 4) AS UNSIGNED) DESC
        LIMIT 1
    ");

    if ($idResult->num_rows > 0) {
        $row = $idResult->fetch_assoc();

        $lastNumber = intval(substr($row["userID"], 3));
        $nextNumber = $lastNumber + 1;
    } else {
        $nextNumber = 1;
    }

    $userID = "USR" . str_pad(
        $nextNumber,
        3,
        "0",
        STR_PAD_LEFT
    );

    /*
    |--------------------------------------------------------------------------
    | Hash password
    |--------------------------------------------------------------------------
    */

    $hashedPassword = password_hash(
        $password,
        PASSWORD_DEFAULT
    );

    $profilePic = null;

    /*
    |--------------------------------------------------------------------------
    | Insert user
    |--------------------------------------------------------------------------
    */

    $insertStmt = $conn->prepare("
        INSERT INTO users
        (
            userID,
            firstName,
            lastName,
            email,
            pass,
            contactNo,
            profilePic,
            barangayID
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ");

    $insertStmt->bind_param(
        "ssssssss",
        $userID,
        $firstName,
        $lastName,
        $email,
        $hashedPassword,
        $contactNo,
        $profilePic,
        $barangayID
    );

    $insertStmt->execute();
    $insertStmt->close();

    /*
    |--------------------------------------------------------------------------
    | Mark registration token as used
    |--------------------------------------------------------------------------
    */

    $usedStmt = $conn->prepare("
        UPDATE registration_email_otps
        SET used_at = NOW()
        WHERE id = ?
          AND used_at IS NULL
    ");

    $usedStmt->bind_param("i", $otpRecordId);
    $usedStmt->execute();

    if ($usedStmt->affected_rows !== 1) {
        $usedStmt->close();

        throw new Exception(
            "Registration token could not be consumed."
        );
    }

    $usedStmt->close();

    // Commit account creation and token consumption together
    $conn->commit();

    respond(true, "Account created successfully.", [
        "userID" => $userID
    ]);

} catch (Throwable $e) {

    $conn->rollback();

    error_log("Registration error: " . $e->getMessage());

    respond(
        false,
        "Failed to create account. Please try again.",
        [],
        500
    );
}

?>
