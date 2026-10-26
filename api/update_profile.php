<?php

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Accept");

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
| Check if user exists
|--------------------------------------------------------------------------
*/

$stmt = $conn->prepare("
    SELECT
        userID,
        profilePic
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

$stmt->close();


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
    | Create upload folder
    */

    $uploadDirectory =
        __DIR__ . DIRECTORY_SEPARATOR .
        ".." . DIRECTORY_SEPARATOR .
        "uploads" . DIRECTORY_SEPARATOR .
        "profile";


    if (!is_dir($uploadDirectory)) {

        if (!mkdir(
            $uploadDirectory,
            0777,
            true
        )) {
            sendResponse(
                false,
                "Failed to create profile upload folder.",
                null,
                500
            );
        }
    }


    /*
    | Make filename based on userID
    |
    | Example:
    | USR001.jpg
    | USR002.jpg
    */

    $safeUserID = preg_replace(
        "/[^A-Za-z0-9_-]/",
        "",
        $userID
    );

    $fileName =
        $safeUserID . "." . $extension;

    $targetFile =
        $uploadDirectory .
        DIRECTORY_SEPARATOR .
        $fileName;


    /*
    | Remove old profile picture if it uses
    | the same user ID but a different extension.
    */

    $possibleExtensions = [
        "jpg",
        "jpeg",
        "png",
        "webp"
    ];

    foreach ($possibleExtensions as $oldExtension) {

        $possibleOldFile =
            $uploadDirectory .
            DIRECTORY_SEPARATOR .
            $safeUserID .
            "." .
            $oldExtension;

        if (
            file_exists($possibleOldFile) &&
            $possibleOldFile !== $targetFile
        ) {
            unlink($possibleOldFile);
        }
    }


    /*
    | Move uploaded file
    */

    if (!move_uploaded_file(
        $file["tmp_name"],
        $targetFile
    )) {
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
    | Remember old physical file so it can
    | be deleted if the database update fails.
    */

    if (
        $oldProfilePic !== null &&
        trim($oldProfilePic) !== ""
    ) {

        $oldRelativePath =
            str_replace(
                "/",
                DIRECTORY_SEPARATOR,
                $oldProfilePic
            );

        $oldPhysicalFilePath =
            dirname(__DIR__) .
            DIRECTORY_SEPARATOR .
            $oldRelativePath;
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
    file_exists($oldPhysicalFilePath) &&
    $oldPhysicalFilePath !== $newUploadedFilePath
) {
    unlink($oldPhysicalFilePath);
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