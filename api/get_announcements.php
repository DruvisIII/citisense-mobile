<?php

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Accept");

if ($_SERVER["REQUEST_METHOD"] === "OPTIONS") {
    http_response_code(200);
    exit;
}

require_once "config.php";

// Check barangayID
if (!isset($_GET["barangayID"]) || trim($_GET["barangayID"]) === "") {
    echo json_encode([
        "success" => false,
        "message" => "Barangay ID is required."
    ]);
    exit;
}

$barangayID = trim($_GET["barangayID"]);

try {

    /*
     * Get announcements intended for the user's barangay.
     *
     * JOIN barangay is included so the API can also return
     * the barangay name.
     */
    $sql = "
        SELECT
            a.announceID,
            a.userID,
            a.barangayID,
            b.barangayName,
            a.title,
            a.content,
            a.datePosted
        FROM announcements a
        LEFT JOIN barangay b
            ON a.barangayID = b.barangayID
        WHERE a.barangayID = ?
        ORDER BY a.datePosted DESC
    ";

    $stmt = $conn->prepare($sql);

    if (!$stmt) {
        throw new Exception("Failed to prepare query.");
    }

    $stmt->bind_param("s", $barangayID);

    if (!$stmt->execute()) {
        throw new Exception("Failed to execute query.");
    }

    $result = $stmt->get_result();

    $announcements = [];

    while ($row = $result->fetch_assoc()) {
        $announcements[] = [
            "announceID" => $row["announceID"],
            "userID" => $row["userID"],
            "barangayID" => $row["barangayID"],
            "barangayName" => $row["barangayName"],
            "title" => $row["title"],
            "content" => $row["content"],
            "datePosted" => $row["datePosted"],
            "images" => []
        ];
    }

    $stmt->close();

    /*
     * Pictures the admin attached (announcement_images table).
     * The admin website saves them, so their web address starts with
     * the admin site's address: ANNOUNCEMENT_MEDIA_BASE_URL, e.g.
     * https://citisense-admin.up.railway.app/
     */
    if ($announcements) {
        $mediaBase = trim((string) getenv("ANNOUNCEMENT_MEDIA_BASE_URL"));
        if ($mediaBase === "") {
            $scheme = (!empty($_SERVER["HTTPS"]) && $_SERVER["HTTPS"] !== "off")
                || (($_SERVER["HTTP_X_FORWARDED_PROTO"] ?? "") === "https") ? "https" : "http";
            $mediaBase = $scheme . "://" . ($_SERVER["HTTP_HOST"] ?? "localhost") . "/";
        }
        $mediaBase = rtrim($mediaBase, "/") . "/";

        $indexByID = [];
        foreach ($announcements as $i => $announcement) {
            $indexByID[(string) $announcement["announceID"]] = $i;
        }

        try {
            $marks = implode(",", array_fill(0, count($indexByID), "?"));
            $imageStmt = $conn->prepare(
                "SELECT announceID, imagePath
                 FROM announcement_images
                 WHERE announceID IN ($marks)
                 ORDER BY sortOrder ASC, imageID ASC"
            );

            if ($imageStmt) {
                $ids = array_map("strval", array_keys($indexByID));
                $imageStmt->bind_param(str_repeat("s", count($ids)), ...$ids);
                $imageStmt->execute();
                $imageResult = $imageStmt->get_result();

                while ($image = $imageResult->fetch_assoc()) {
                    $path = trim((string) $image["imagePath"]);
                    if ($path === "") {
                        continue;
                    }

                    $url = preg_match('~^https?://~i', $path)
                        ? $path
                        : $mediaBase . implode("/", array_map("rawurlencode", explode("/", ltrim($path, "/"))));

                    $i = $indexByID[(string) $image["announceID"]] ?? null;
                    if ($i !== null) {
                        $announcements[$i]["images"][] = $url;
                    }
                }

                $imageStmt->close();
            }
        } catch (Throwable $imageError) {
            // No announcement_images table yet: show announcements without pictures.
            error_log("Announcement images unavailable: " . $imageError->getMessage());
        }
    }

    echo json_encode([
        "success" => true,
        "message" => "Announcements retrieved successfully.",
        "data" => $announcements
    ]);

} catch (Exception $e) {

    http_response_code(500);

    echo json_encode([
        "success" => false,
        "message" => $e->getMessage()
    ]);
}

$conn->close();

?>