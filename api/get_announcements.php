<?php

header("Content-Type: application/json; charset=utf-8");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Accept");

if ($_SERVER["REQUEST_METHOD"] === "OPTIONS") {
    http_response_code(200);
    exit;
}

require_once "config.php";
require_once __DIR__ . "/time_helpers.php";

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
            "datePosted" => citisense_iso_time($conn, $row["datePosted"]),
            "postedBy" => null,
            "commentCount" => 0,
            "images" => []
        ];
    }

    $stmt->close();

    /*
     * Who posted each announcement (an admin row in users) and how many
     * visible comments it has. Simple lookups, no JOINs (see
     * conversation_common.php about collations).
     */
    if ($announcements) {
        $nameStmt = $conn->prepare("SELECT firstName, lastName FROM users WHERE userID = ? LIMIT 1");
        $nameCache = [];
        foreach ($announcements as $i => $announcement) {
            $posterID = (string) ($announcement["userID"] ?? "");
            if ($posterID === "") {
                continue;
            }
            if (!array_key_exists($posterID, $nameCache)) {
                $nameStmt->bind_param("s", $posterID);
                $nameStmt->execute();
                $nameRow = $nameStmt->get_result()->fetch_assoc();
                $nameCache[$posterID] = $nameRow
                    ? trim(($nameRow["firstName"] ?? "") . " " . ($nameRow["lastName"] ?? ""))
                    : "";
            }
            if ($nameCache[$posterID] !== "") {
                $announcements[$i]["postedBy"] = $nameCache[$posterID];
            }
        }
        $nameStmt->close();

        try {
            $countStmt = $conn->prepare(
                "SELECT COUNT(*) AS total FROM announcement_comments WHERE announceID = ? AND isHidden = 0"
            );
            foreach ($announcements as $i => $announcement) {
                $id = (int) $announcement["announceID"];
                $countStmt->bind_param("i", $id);
                $countStmt->execute();
                $announcements[$i]["commentCount"] = (int) ($countStmt->get_result()->fetch_assoc()["total"] ?? 0);
            }
            $countStmt->close();
        } catch (Throwable $countError) {
            // No comments table yet: counts stay 0.
        }
    }

    /*
     * Pictures the admin attached (announcement_images table).
     * They are saved by the admin website, so the app loads them
     * through media.php, which finds the file on this server or
     * downloads it from the admin website (ANNOUNCEMENT_MEDIA_BASE_URL).
     */
    if ($announcements) {
        require_once __DIR__ . "/media_common.php";

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

                    $url = citisense_media_url($path);
                    if ($url === "") {
                        error_log("CitiSense announcement image skipped (unexpected path): " . $path);
                        continue;
                    }

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

} catch (Throwable $e) {

    error_log("CitiSense announcements error: " . $e->getMessage());
    http_response_code(500);

    echo json_encode([
        "success" => false,
        "message" => "We could not load announcements. Please try again."
    ]);
}

$conn->close();

?>