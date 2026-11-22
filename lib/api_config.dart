const bool useRailway = true;

const String serverBaseUrl = useRailway
    ? 'https://citisense-api-production.up.railway.app'
    : 'http://192.168.1.48/citisense';

const String apiBaseUrl = useRailway ? serverBaseUrl : '$serverBaseUrl/api';

const String imageBaseUrl = serverBaseUrl;
