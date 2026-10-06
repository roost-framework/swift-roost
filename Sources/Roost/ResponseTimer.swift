import HTTPTypes
import Nexus

/// A plug that measures request processing time and sets the
/// `X-Response-Time` header on the response.
public func responseTimer() -> Plug {
    { conn in
        let start = ContinuousClock.now
        return conn.registerBeforeSend { c in
            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.attoseconds / 1_000_000_000_000_000
            return c.putRespHeader(HTTPField.Name("X-Response-Time")!, "\(ms)ms")
        }
    }
}
