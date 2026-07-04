import Foundation

/// Native client for the Hyundai BlueLink USA owner API — the same one the
/// MyHyundai app (and BetterBlue) talk to. Endpoints, headers, and payloads
/// mirror the reference implementation in the open-source
/// hyundai_kia_connect_api project (HyundaiBlueLinkApiUSA).
actor BlueLinkClient {
    static let host = "api.telematics.hyundaiusa.com"
    private static let loginBase = "https://\(host)/v2/ac/"
    private static let apiBase = "https://\(host)/ac/v2/"
    private static let clientID = "m66129Bb-em93-SPAHYN-bZ91-am4540zp19920"
    private static let clientSecret = "v558o935-6nne-423i-baa8"

    private let session: URLSession
    private var username = ""
    private var password = ""
    private var pin = ""
    private var token: BlueLinkToken?

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config)
    }

    var isConfigured: Bool { !username.isEmpty && !password.isEmpty }

    func setCredentials(username: String, password: String, pin: String) {
        self.username = username
        self.password = password
        self.pin = pin
        self.token = nil
    }

    func clearCredentials() {
        username = ""
        password = ""
        pin = ""
        token = nil
    }

    // MARK: - Headers

    private var baseHeaders: [String: String] {
        let offsetHours = TimeZone.current.secondsFromGMT() / 3600
        return [
            "Content-Type": "application/json;charset=UTF-8",
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "en-US,en;q=0.9",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.142 Safari/537.36",
            "Host": Self.host,
            "Origin": "https://\(Self.host)",
            "Referer": "https://\(Self.host)/login",
            "From": "SPA",
            "To": "ISS",
            "Language": "0",
            "Offset": String(offsetHours),
            "Sec-Fetch-Dest": "empty",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Site": "same-origin",
            "refresh": "false",
            "encryptFlag": "false",
            "brandIndicator": "H",
            "client_id": Self.clientID,
            "clientSecret": Self.clientSecret,
        ]
    }

    private func authenticatedHeaders() async throws -> [String: String] {
        let token = try await validToken()
        var headers = baseHeaders
        headers["username"] = username
        headers["accessToken"] = token.accessToken
        headers["blueLinkServicePin"] = pin
        return headers
    }

    private func vehicleHeaders(for vehicle: BlueLinkVehicle) async throws -> [String: String] {
        var headers = try await authenticatedHeaders()
        headers["registrationId"] = vehicle.regId
        headers["gen"] = String(vehicle.generation)
        headers["vin"] = vehicle.vin
        return headers
    }

    // MARK: - HTTP plumbing

    private func send(
        _ method: String,
        url: String,
        headers: [String: String],
        jsonBody: [String: Any]? = nil
    ) async throws -> (Any?, HTTPURLResponse) {
        guard let requestURL = URL(string: url) else {
            throw BlueLinkError.malformedResponse("bad URL \(url)")
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BlueLinkError.malformedResponse("non-HTTP response")
        }

        // Remote commands return HTTP 200 with an empty body on success.
        let json: Any? = data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data)

        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw BlueLinkError.httpError(http.statusCode, bodyText)
        }
        if let dict = json as? [String: Any], let errorCode = JSONPath.string(dict, "errorCode") {
            let message = JSONPath.string(dict, "errorMessage") ?? "unknown error"
            if errorCode == "502" {
                throw BlueLinkError.badCredentials(message)
            }
            throw BlueLinkError.apiError(code: errorCode, message: message)
        }
        return (json, http)
    }

    // MARK: - Auth

    @discardableResult
    func login() async throws -> BlueLinkToken {
        guard isConfigured else { throw BlueLinkError.notLoggedIn }
        let body: [String: Any] = ["username": username, "password": password]
        let (json, _) = try await send("POST", url: Self.loginBase + "oauth/token",
                                       headers: baseHeaders, jsonBody: body)
        return try storeToken(from: json)
    }

    private func storeToken(from json: Any?) throws -> BlueLinkToken {
        guard let access = JSONPath.string(json, "access_token"),
              let refresh = JSONPath.string(json, "refresh_token") else {
            let message = JSONPath.string(json, "errorMessage") ?? "no access token returned"
            throw BlueLinkError.badCredentials(message)
        }
        let expiresIn = JSONPath.double(json, "expires_in") ?? 1800
        let newToken = BlueLinkToken(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
        token = newToken
        return newToken
    }

    private func validToken() async throws -> BlueLinkToken {
        if let token, token.isValid { return token }
        // Try refresh-token exchange first (fast); fall back to full login.
        if let token {
            let body: [String: Any] = [
                "username": username,
                "password": password,
                "grant_type": "refresh_token",
                "refresh_token": token.refreshToken,
            ]
            if let (json, _) = try? await send("POST", url: Self.loginBase + "oauth/token",
                                               headers: baseHeaders, jsonBody: body),
               let refreshed = try? storeToken(from: json) {
                return refreshed
            }
        }
        return try await login()
    }

    // MARK: - Vehicles

    func fetchVehicles() async throws -> [BlueLinkVehicle] {
        let headers = try await authenticatedHeaders()
        let (json, _) = try await send("GET", url: Self.apiBase + "enrollment/details/" + username,
                                       headers: headers)
        guard let enrolled = JSONPath.value(json, "enrolledVehicleDetails") as? [Any] else {
            throw BlueLinkError.malformedResponse("missing enrolledVehicleDetails")
        }
        let vehicles: [BlueLinkVehicle] = enrolled.compactMap { entry in
            guard let details = JSONPath.value(entry, "vehicleDetails") as? [String: Any],
                  let regId = JSONPath.string(details, "regid"),
                  let vin = JSONPath.string(details, "vin") else { return nil }
            return BlueLinkVehicle(
                regId: regId,
                vin: vin,
                nickname: JSONPath.string(details, "nickName") ?? "My Ioniq 5",
                modelCode: JSONPath.string(details, "modelCode") ?? "",
                generation: JSONPath.int(details, "vehicleGeneration") ?? 2,
                isEV: JSONPath.string(details, "evStatus") == "E"
            )
        }
        guard !vehicles.isEmpty else { throw BlueLinkError.noVehicles }
        return vehicles
    }

    /// Odometer lives in the enrollment payload, not vehicleStatus.
    private func fetchOdometerMiles(vin: String) async throws -> Double? {
        let headers = try await authenticatedHeaders()
        let (json, _) = try await send("GET", url: Self.apiBase + "enrollment/details/" + username,
                                       headers: headers)
        guard let enrolled = JSONPath.value(json, "enrolledVehicleDetails") as? [Any] else { return nil }
        for entry in enrolled {
            if JSONPath.string(entry, "vehicleDetails.vin") == vin {
                return JSONPath.double(entry, "vehicleDetails.odometer")
            }
        }
        return nil
    }

    // MARK: - Status

    /// Cached status is what the car last pushed; `forceRefresh` wakes the car
    /// (slower, uses 12 V battery — the API rate-limits it).
    func fetchStatus(for vehicle: BlueLinkVehicle, forceRefresh: Bool) async throws -> BlueLinkStatus {
        var headers = try await vehicleHeaders(for: vehicle)
        if forceRefresh { headers["REFRESH"] = "true" }
        let (json, _) = try await send("GET", url: Self.apiBase + "rcs/rvs/vehicleStatus",
                                       headers: headers)
        guard let statusDict = JSONPath.value(json, "vehicleStatus") as? [String: Any] else {
            throw BlueLinkError.malformedResponse("missing vehicleStatus")
        }

        var status = parseStatus(statusDict)
        status.odometerMiles = try? await fetchOdometerMiles(vin: vehicle.vin)

        // Location is a separate, rate-limited endpoint; only poke it on a
        // forced refresh and never let it fail the whole status fetch.
        if forceRefresh, status.latitude == nil {
            if let location = try? await fetchLocation(for: vehicle) {
                status.latitude = location.lat
                status.longitude = location.lon
            }
        }
        return status
    }

    private func parseStatus(_ s: [String: Any]) -> BlueLinkStatus {
        var status = BlueLinkStatus()
        status.socPercent = JSONPath.double(s, "evStatus.batteryStatus")
        status.isCharging = JSONPath.bool(s, "evStatus.batteryCharge")
        if let plugin = JSONPath.int(s, "evStatus.batteryPlugin") {
            status.isPluggedIn = plugin != 0
        }

        if let rangeValue = JSONPath.double(s, "evStatus.drvDistance.0.rangeByFuel.evModeRange.value") {
            // unit 1 = km, 3 = miles (US accounts report 3)
            let unit = JSONPath.int(s, "evStatus.drvDistance.0.rangeByFuel.evModeRange.unit") ?? 3
            status.rangeMiles = unit == 1 ? rangeValue * 0.621371 : rangeValue
        }

        status.minutesToTargetSOC = JSONPath.int(s, "evStatus.remainTime2.atc.value")

        if let socList = JSONPath.value(s, "evStatus.reservChargeInfos.targetSOClist") as? [Any] {
            for entry in socList {
                let level = JSONPath.int(entry, "targetSOClevel")
                switch JSONPath.int(entry, "plugType") {
                case 0: status.dcChargeLimit = level
                case 1: status.acChargeLimit = level
                default: break
                }
            }
        }

        status.twelveVoltPercent = JSONPath.double(s, "battery.batSoc")
        status.isLocked = JSONPath.bool(s, "doorLock")
        status.climateOn = JSONPath.bool(s, "airCtrlOn")

        let doorPaths = ["doorOpen.frontLeft", "doorOpen.frontRight",
                         "doorOpen.backLeft", "doorOpen.backRight",
                         "hoodOpen", "trunkOpen"]
        status.anyDoorOpen = doorPaths.contains { JSONPath.bool(s, $0) == true }

        status.tirePressureWarning = JSONPath.bool(s, "tirePressureLamp.tirePressureWarningLampAll")

        if let dateString = JSONPath.string(s, "dateTime") {
            let formatter = ISO8601DateFormatter()
            status.reportedAt = formatter.date(from: dateString)
        }

        status.latitude = JSONPath.double(s, "vehicleLocation.coord.lat")
        status.longitude = JSONPath.double(s, "vehicleLocation.coord.lon")
        return status
    }

    private func fetchLocation(for vehicle: BlueLinkVehicle) async throws -> (lat: Double, lon: Double)? {
        let headers = try await vehicleHeaders(for: vehicle)
        let (json, _) = try await send("GET", url: Self.apiBase + "rcs/rfc/findMyCar",
                                       headers: headers)
        guard let lat = JSONPath.double(json, "coord.lat"),
              let lon = JSONPath.double(json, "coord.lon") else { return nil }
        return (lat, lon)
    }

    // MARK: - Remote commands

    func lock(_ vehicle: BlueLinkVehicle) async throws {
        try await doorCommand(vehicle, path: "rcs/rdo/off")
    }

    func unlock(_ vehicle: BlueLinkVehicle) async throws {
        try await doorCommand(vehicle, path: "rcs/rdo/on")
    }

    private func doorCommand(_ vehicle: BlueLinkVehicle, path: String) async throws {
        var headers = try await vehicleHeaders(for: vehicle)
        headers["APPCLOUD-VIN"] = vehicle.vin
        let body: [String: Any] = ["userName": username, "vin": vehicle.vin]
        _ = try await send("POST", url: Self.apiBase + path, headers: headers, jsonBody: body)
    }

    func startClimate(_ vehicle: BlueLinkVehicle, tempF: Int, defrost: Bool) async throws {
        let headers = try await vehicleHeaders(for: vehicle)
        var body: [String: Any] = [
            "airCtrl": 1,
            "airTemp": ["value": String(tempF), "unit": 1],
            "defrost": defrost,
            "heating1": 0,
        ]
        if vehicle.generation >= 3 {
            body["igniOnDuration"] = 10
            body["seatHeaterVentInfo"] = [
                "drvSeatHeatState": 0, "astSeatHeatState": 0,
                "rlSeatHeatState": 0, "rrSeatHeatState": 0,
            ]
        }
        _ = try await send("POST", url: Self.apiBase + "evc/fatc/start",
                           headers: headers, jsonBody: body)
    }

    func stopClimate(_ vehicle: BlueLinkVehicle) async throws {
        let headers = try await vehicleHeaders(for: vehicle)
        _ = try await send("POST", url: Self.apiBase + "evc/fatc/stop", headers: headers)
    }

    func startCharge(_ vehicle: BlueLinkVehicle) async throws {
        let headers = try await vehicleHeaders(for: vehicle)
        _ = try await send("POST", url: Self.apiBase + "evc/charge/start", headers: headers)
    }

    func stopCharge(_ vehicle: BlueLinkVehicle) async throws {
        let headers = try await vehicleHeaders(for: vehicle)
        _ = try await send("POST", url: Self.apiBase + "evc/charge/stop", headers: headers)
    }
}
