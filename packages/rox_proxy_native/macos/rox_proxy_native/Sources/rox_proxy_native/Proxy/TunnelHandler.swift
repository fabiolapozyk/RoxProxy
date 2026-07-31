import NIOCore
import os.log

/// Blindly relays bytes between two channels (inbound ↔ upstream).
///
/// Installed after the HTTP codec is removed from the pipeline when the proxy
/// establishes a CONNECT tunnel.  One instance is added to each side; the
/// `peer` property points to the other channel so bytes can be forwarded.
final class TunnelHandler: ChannelDuplexHandler {
    typealias InboundIn   = ByteBuffer
    typealias InboundOut  = ByteBuffer
    typealias OutboundIn  = ByteBuffer
    typealias OutboundOut = ByteBuffer

    /// The other end of the tunnel.  Set right after both channels are ready.
    var peer: Channel?

    // MARK: - Inbound → peer

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard let peer else {
            ProxyLogger.http.debug("TunnelHandler: no peer, closing")
            context.close(promise: nil)
            return
        }
        // Forward to peer; back-pressure: pause reads if peer write buffer grows
        let buf = unwrapInboundIn(data)
        ProxyLogger.http.debug("TunnelHandler: forwarding %d bytes to peer", buf.readableBytes)
        peer.writeAndFlush(NIOAny(buf)).whenFailure { error in
            ProxyLogger.http.error("TunnelHandler: write to peer failed: %{public}@", error.localizedDescription)
            context.close(promise: nil)
        }
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        ProxyLogger.http.debug("TunnelHandler: channel read complete")
        context.flush()
    }

    // MARK: - Closure propagation

    func channelInactive(context: ChannelHandlerContext) {
        ProxyLogger.http.debug("TunnelHandler: channel inactive")
        peer?.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        ProxyLogger.http.error("TunnelHandler: error caught: %{public}@", error.localizedDescription)
        peer?.close(promise: nil)
        context.close(promise: nil)
    }
}
