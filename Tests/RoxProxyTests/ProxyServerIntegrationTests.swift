import Testing
import NIOCore
import NIOHTTP1
@testable import RoxProxy

// MARK: - ProxyServer Integration Tests

@MainActor
struct ProxyServerIntegrationTests {
    
    // MARK: - Lifecycle Tests
    
    @Test func serverStartsSuccessfully() async {
        // Given
        let store = ProxySessionStore()
        let settingsStore = SettingsStore()
        
        let server = ProxyServer(
            port: 18999,
            store: store,
            settingsStore: settingsStore,
            certificateAuthority: nil,
            domainCertCache: nil
        )
        
        // When
        do {
            try await server.start()
            // If we get here, server started successfully
            #expect(true)
            
            // Cleanup
            try? await server.stop()
        } catch {
            // Server failed to start
            Issue.record("Server failed to start: \(error)")
        }
    }
    
    @Test func serverStopsSuccessfully() async {
        // Given
        let store = ProxySessionStore()
        let settingsStore = SettingsStore()
        
        let server = ProxyServer(
            port: 18998,
            store: store,
            settingsStore: settingsStore,
            certificateAuthority: nil,
            domainCertCache: nil
        )
        
        // When
        do {
            try await server.start()
            try await server.stop()
            #expect(true)
        } catch {
            Issue.record("Server stop failed: \(error)")
        }
    }
}
