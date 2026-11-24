<?php

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Accept, X-Auth-Token");

if ($_SERVER["REQUEST_METHOD"] === "OPTIONS") {
    http_response_code(200);
    exit;
}

require_once "config.php";

/*
|--------------------------------------------------------------------------
| Helper function
|--------------------------------------------------------------------------
*/

function sendResponse($success, $message, $data = null, $statusCode = 200)
{
    http_response_code($statusCode);

    $response = [
        "success" => $success,
        "message" => $message
    ];

    if ($data !== null) {
        $response["data"] = $data;
    }

    echo json_encode($response);
    exit;
}


/*
|--------------------------------------------------------------------------
| Only POST is allowed
|--------------------------------------------------------------------------
*/

if ($_SERVER["REQUEST_METHOD"] !== "POST") {
    sendResponse(
        false,
        "Only POST requests are allowed.",
        null,
        405
    );
}


/*
|--------------------------------------------------------------------------
| Get form values
|--------------------------------------------------------------------------
*/

$userID = isset($_POST["userID"])
    ? trim($_POST["userID"])
    : "";

$firstName = isset($_POST["firstName"])
    ? trim($_POST["firstName"])
    : "";

$lastName = isset($_POST["lastName"])
    ? trim($_POST["lastName"])
    : "";

$email = isset($_POST["email"])
    ? trim($_POST["email"])
    : "";

$contactNo = isset($_POST["contactNo"])
    ? trim($_POST["contactNo"])
    : "";

$barangayID = isset($_POST["barangayID"])
    ? trim($_POST["barangayID"])
    : "";


/*
|--------------------------------------------------------------------------
| Validate required fields
|--------------------------------------------------------------------------
*/

if (
    $userID === "" ||
    $firstName === "" ||
    $lastName === "" ||
    $email === "" ||
    $contactNo === "" ||
    $barangayID === ""
) {
    sendResponse(
        false,
        "All required fields must be provided.",
        null,
        400
    );
}


/*
|--------------------------------------------------------------------------
| Only the logged-in user can change their own profile
|--------------------------------------------------------------------------
*/

require_once __DIR__ . "/auth.php";
citisense_require_user($conn, $userID);


/*
|--------------------------------------------------------------------------
| Validate email
|--------------------------------------------------------------------------
*/

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    sendResponse(
        false,
        "Please provide a valid email address.",
        null,
        400
    );
}


/*
|--------------------------------------------------------------------------
| Validate Philippine mobile number (stored as 09XXXXXXXXX)
|--------------------------------------------------------------------------
*/

require_once __DIR__ . "/validation.php";

$normalizedContact = citisense_normalize_ph_mobile($contactNo);

if ($normalizedContact === null) {
    sendResponse(false, CITISENSE_PHONE_ERROR, null, 400);
}

$contactNo = $normalizedContact;


/*
|--------------------------------------------------------------------------
| Check if user exists
|--------------------------------------------------------------------------
*/

$stmt = $conn->prepare("
    SELECT
        userID,
        profilePic,
        email
    FROM users
    WHERE userID = ?
    LIMIT 1
");

if (!$stmt) {
    sendResponse(
        false,
        "Failed to prepare user query.",
        null,
        500
    );
}

$stmt->bind_param("s", $userID);
$stmt->execute();

$result = $stmt->get_result();

if ($result->num_rows === 0) {
    $stmt->close();

    sendResponse(
        false,
        "User not found.",
        null,
        404
    );
}

$user = $result->fetch_assoc();

$oldProfilePic = $user["profilePic"];

$currentEmail = (string)$user["email"];

$stmt->close();


/*
|--------------------------------------------------------------------------
| Only save a verified email
|--------------------------------------------------------------------------
|
| A new email is saved by verify_email_change_otp.php after the user
| confirms the code sent to it. This endpoint never changes the email
| on its own, so an unverified email is rejected here.
|
*/

if (strtolower(trim($currentEmail)) !== strtolower($email)) {
    sendResponse(
        false,
        "Please verify your new email address before saving it.",
        null,
        403
    );
}

// Keep the verified email exactly as stored.
$email = $currentEmail;


/*
|--------------------------------------------------------------------------
| Check if barangay exists
|--------------------------------------------------------------------------
*/

$stmt = $conn->prepare("
    SELECT barangayID, barangayName
    FROM barangay
    WHERE barangayID = ?
    LIMIT 1
");

if (!$stmt) {
    sendResponse(
        false,
        "Failed to prepare barangay query.",
        null,
        500
    );
}

$stmt->bind_param("s", $barangayID);
$stmt->execute();

$result = $stmt->get_result();

if ($result->num_rows === 0) {
    $stmt->close();

    sendResponse(
        false,
        "Selected barangay does not exist.",
        null,
        400
    );
}

$barangay = $result->fetch_assoc();

$stmt->close();

$barangayName = $barangay["barangayName"];


/*
|--------------------------------------------------------------------------
| Check if email is already being used by another user
|--------------------------------------------------------------------------
*/

$stmt = $conn->prepare("
    SELECT userID
    FROM users
    WHERE email = ?
      AND userID != ?
    LIMIT 1
");

if (!$stmt) {
    sendResponse(
        false,
        "Failed to prepare email query.",
        null,
        500
    );
}

$stmt->bind_param(
    "ss",
    $email,
    $userID
);

$stmt->execute();

$result = $stmt->get_result();

if ($result->num_rows > 0) {
    $stmt->close();

    sendResponse(
        false,
        "That email address is already being used by another account.",
        null,
        409
    );
}

$stmt->close();


/*
|--------------------------------------------------------------------------
| Profile picture variables
|--------------------------------------------------------------------------
*/

$newProfilePic = $oldProfilePic;
$newUploadedFilePath = null;
$oldPhysicalFilePath = null;

$hasNewProfilePicture = (
    isset($_FILES["profilePicture"]) &&
    $_FILES["profilePicture"]["error"] !== UPLOAD_ERR_NO_FILE
);


/*
|--------------------------------------------------------------------------
| Handle profile picture upload
|--------------------------------------------------------------------------
*/

if ($hasNewProfilePicture) {

    $file = $_FILES["profilePicture"];


    /*
    | Check upload error
    */

    if ($file["error"] !== UPLOAD_ERR_OK) {

        $uploadErrorMessage = "Failed to upload profile picture.";

        switch ($file["error"]) {
            case UPLOAD_ERR_INI_SIZE:
            case UPLOAD_ERR_FORM_SIZE:
                $uploadErrorMessage =
                    "The profile picture is too large.";
                break;

            case UPLOAD_ERR_PARTIAL:
                $uploadErrorMessage =
                    "The profile picture was only partially uploaded.";
                break;

            case UPLOAD_ERR_NO_TMP_DIR:
                $uploadErrorMessage =
                    "Server temporary folder is missing.";
                break;

            case UPLOAD_ERR_CANT_WRITE:
                $uploadErrorMessage =
                    "The server could not save the uploaded file.";
                break;

            case UPLOAD_ERR_EXTENSION:
                $uploadErrorMessage =
                    "A server extension stopped the upload.";
                break;
        }

        sendResponse(
            false,
            $uploadErrorMessage,
            null,
            400
        );
    }


    /*
    | Maximum file size: 10 MB
    */

    $maxFileSize = 10 * 1024 * 1024;

    if ($file["size"] > $maxFileSize) {
        sendResponse(
            false,
            "Profile picture must not exceed 10 MB.",
            null,
            400
        );
    }


    /*
    | Verify actual MIME type
    */

    $finfo = finfo_open(FILEINFO_MIME_TYPE);

    if (!$finfo) {
        sendResponse(
            false,
            "Unable to verify the uploaded image.",
            null,
            500
        );
    }

    $mimeType = finfo_file(
        $finfo,
        $file["tmp_name"]
    );

    finfo_close($finfo);


    /*
    | Allowed image types
    */

    $allowedTypes = [
        "image/jpeg" => "jpg",
        "image/png"  => "png",
        "image/webp" => "webp"
    ];

    if (!isset($allowedTypes[$mimeType])) {
        sendResponse(
            false,
            "Only JPG, PNG, and WEBP images are allowed.",
            null,
            400
        );
    }

    $extension = $allowedTypes[$mimeType];


    /*
    | Upload folder: the same place as report photos, so the picture is
    | served at <server>/uploads/profile/... (XAMPP: citisense/uploads,
    | Railway: api/uploads, where the api folder is the web root).
    | UPLOAD_ROOT can override both, e.g. a Railway volume.
    */

    $parentUploads = dirname(__DIR__) . DIRECTORY_SEPARATOR . "uploads";

    $uploadRoot = getenv("UPLOAD_ROOT") ?: (
        is_dir($parentUploads)
            ? $parentUploads
            : __DIR__ . DIRECTORY_SEPARATOR . "uploads"
    );

    $uploadDirectory =
        rtrim($uploadRoot, "/\\") .
        DIRECTORY_SEPARATOR .
        "profile";

    if (!is_dir($uploadDirectory) && !mkdir($uploadDirectory, 0775, true) && !is_dir($uploadDirectory)) {
        sendResponse(
            false,
            "Failed to create profile upload folder.",
            null,
            500
        );
    }


    /*
    | A new file name for every upload (e.g. USR001_1764000000_a1b2c3.jpg).
    | Reusing USR001.jpg made phones keep showing the old, cached picture.
    */

    $safeUserID = preg_replace(
        "/[^A-Za-z0-9_-]/",
        "",
        $userID
    );

    $fileName =
        $safeUserID . "_" . time() . "_" . bin2hex(random_bytes(3)) . "." . $extension;

    $targetFile =
        $uploadDirectory .
        DIRECTORY_SEPARATOR .
        $fileName;


    /*
    | Move uploaded file, then make sure it really is there.
    */

    if (
        !move_uploaded_file($file["tmp_name"], $targetFile) ||
        !is_file($targetFile) ||
        filesize($targetFile) === 0
    ) {
        sendResponse(
            false,
            "Failed to save the profile picture.",
            null,
            500
        );
    }


    /*
    | Path saved in database
    */

    $newProfilePic =
        "uploads/profile/" .
        $fileName;

    $newUploadedFilePath = $targetFile;


    /*
    | Remember the old picture so it can be deleted once the database
    | points to the new one (only files inside the profile folder).
    */

    if (
        $oldProfilePic !== null &&
        str_starts_with(trim($oldProfilePic), "uploads/profile/")
    ) {
        $oldCandidate = realpath(
            $uploadDirectory . DIRECTORY_SEPARATOR . basename(trim($oldProfilePic))
        );
        $profileFolder = realpath($uploadDirectory);

        if (
            $oldCandidate !== false &&
            $profileFolder !== false &&
            dirname($oldCandidate) === $profileFolder
        ) {
            $oldPhysicalFilePath = $oldCandidate;
        }
    }
}


/*
|--------------------------------------------------------------------------
| Update database
|--------------------------------------------------------------------------
*/

$sql = "
    UPDATE users
    SET
        firstName = ?,
        lastName = ?,
        email = ?,
        contactNo = ?,
        barangayID = ?,
        profilePic = ?
    WHERE userID = ?
";


$stmt = $conn->prepare($sql);

if (!$stmt) {

    /*
    | Remove newly uploaded image if the
    | database query could not be prepared.
    */

    if (
        $newUploadedFilePath !== null &&
        file_exists($newUploadedFilePath)
    ) {
        unlink($newUploadedFilePath);
    }

    sendResponse(
        false,
        "Failed to prepare profile update.",
        null,
        500
    );
}


$stmt->bind_param(
    "sssssss",
    $firstName,
    $lastName,
    $email,
    $contactNo,
    $barangayID,
    $newProfilePic,
    $userID
);


if (!$stmt->execute()) {

    /*
    | Remove newly uploaded image if
    | database update failed.
    */

    if (
        $newUploadedFilePath !== null &&
        file_exists($newUploadedFilePath)
    ) {
        unlink($newUploadedFilePath);
    }

    $error = $stmt->error;

    $stmt->close();

    sendResponse(
        false,
        "Failed to update profile: " . $error,
        null,
        500
    );
}

$stmt->close();


/*
| Confirm the database now has the new picture before reporting success.
*/

if ($hasNewProfilePicture) {
    $check = $conn->prepare("SELECT profilePic FROM users WHERE userID = ? LIMIT 1");
    $check->bind_param("s", $userID);
    $check->execute();
    $savedPic = (string) ($check->get_result()->fetch_assoc()["profilePic"] ?? "");
    $check->close();

    if ($savedPic !== $newProfilePic) {
        if ($newUploadedFilePath !== null && is_file($newUploadedFilePath)) {
            @unlink($newUploadedFilePath);
        }
        sendResponse(false, "Failed to save the profile picture.", null, 500);
    }
}


/*
|--------------------------------------------------------------------------
| Delete old physical profile picture
|--------------------------------------------------------------------------
|
| Only delete the old file after the database
| has successfully been updated.
|
*/

if (
    $hasNewProfilePicture &&
    $oldPhysicalFilePath !== null &&
    is_file($oldPhysicalFilePath) &&
    realpath($oldPhysicalFilePath) !== realpath((string) $newUploadedFilePath)
) {
    @unlink($oldPhysicalFilePath);
}


/*
|--------------------------------------------------------------------------
| Return updated user information
|--------------------------------------------------------------------------
*/

sendResponse(
    true,
    "Profile updated successfully.",
    [
        "userID" => $userID,
        "firstName" => $firstName,
        "lastName" => $lastName,
        "email" => $email,
        "contactNo" => $contactNo,
        "barangayID" => $barangayID,
        "barangayName" => $barangayName,
        "profilePic" => $newProfilePic
    ]
);


$conn->close();

?>