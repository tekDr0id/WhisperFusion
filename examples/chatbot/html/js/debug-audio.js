// Debug script to verify browser audio capture and WebSocket communication
// Add this to browser console to debug audio issues

class AudioDebugger {
    constructor() {
        this.isRecording = false;
        this.websocketUrl = 'ws://' + window.location.host + '/transcription';
        this.websocket = null;
        this.audioContext = null;
        this.audioWorkletNode = null;
        this.bytesReceived = 0;
        this.bytesSent = 0;
    }

    async startDebugSession() {
        console.log('🎯 Starting WhisperFusion Audio Debug Session');
        console.log('=' * 50);
        
        // Test 1: Check browser capabilities
        this.checkBrowserCapabilities();
        
        // Test 2: Test WebSocket connection
        await this.testWebSocketConnection();
        
        // Test 3: Test microphone access
        await this.testMicrophoneAccess();
        
        // Test 4: Test audio capture and send
        await this.testAudioCaptureAndSend();
    }

    checkBrowserCapabilities() {
        console.log('🔍 Checking browser capabilities...');
        
        const capabilities = {
            'WebRTC': !!navigator.mediaDevices?.getUserMedia,
            'AudioContext': !!(window.AudioContext || window.webkitAudioContext),
            'AudioWorklet': !!window.AudioWorkletNode,
            'WebSockets': !!window.WebSocket,
            'HTTPS': location.protocol === 'https:' || location.hostname === 'localhost'
        };
        
        console.table(capabilities);
        
        const issues = Object.entries(capabilities).filter(([key, value]) => !value);
        if (issues.length > 0) {
            console.warn('⚠️  Missing capabilities:', issues.map(([key]) => key));
        } else {
            console.log('✅ All browser capabilities available');
        }
    }

    async testWebSocketConnection() {
        console.log('🔌 Testing WebSocket connection...');
        
        return new Promise((resolve) => {
            const testWs = new WebSocket(this.websocketUrl);
            const timeout = setTimeout(() => {
                console.error('❌ WebSocket connection timeout');
                testWs.close();
                resolve(false);
            }, 5000);
            
            testWs.onopen = () => {
                console.log('✅ WebSocket connected successfully');
                clearTimeout(timeout);
                testWs.close();
                resolve(true);
            };
            
            testWs.onerror = (error) => {
                console.error('❌ WebSocket connection error:', error);
                clearTimeout(timeout);
                resolve(false);
            };
            
            testWs.onclose = (event) => {
                if (event.code !== 1000) {
                    console.warn('⚠️  WebSocket closed unexpectedly:', event.code, event.reason);
                }
            };
        });
    }

    async testMicrophoneAccess() {
        console.log('🎤 Testing microphone access...');
        
        try {
            const stream = await navigator.mediaDevices.getUserMedia({ 
                audio: {
                    sampleRate: 16000,
                    channelCount: 1,
                    echoCancellation: true,
                    noiseSuppression: true
                }
            });
            
            console.log('✅ Microphone access granted');
            console.log('🔧 Audio settings:', {
                tracks: stream.getAudioTracks().length,
                settings: stream.getAudioTracks()[0]?.getSettings()
            });
            
            // Stop the test stream
            stream.getTracks().forEach(track => track.stop());
            return true;
            
        } catch (error) {
            console.error('❌ Microphone access failed:', error.message);
            if (error.name === 'NotAllowedError') {
                console.log('💡 Solution: Grant microphone permission in browser settings');
            }
            return false;
        }
    }

    async testAudioCaptureAndSend() {
        console.log('📡 Testing audio capture and WebSocket sending...');
        
        try {
            // Setup audio context
            const AudioCtx = window.AudioContext || window.webkitAudioContext;
            this.audioContext = new AudioCtx({ sampleRate: 16000 });
            
            // Setup WebSocket
            this.websocket = new WebSocket(this.websocketUrl);
            
            await new Promise((resolve, reject) => {
                this.websocket.onopen = resolve;
                this.websocket.onerror = reject;
                setTimeout(() => reject(new Error('WebSocket timeout')), 5000);
            });
            
            console.log('✅ WebSocket ready for audio data');
            
            // Setup WebSocket message handling
            this.websocket.onmessage = (event) => {
                this.bytesReceived += event.data.length || 0;
                console.log('📥 Received response:', event.data.substring(0, 100) + '...');
            };
            
            // Get microphone stream
            const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
            
            // Load audio worklet
            await this.audioContext.audioWorklet.addModule('js/audio-processor.js');
            
            // Create audio processing chain
            const source = this.audioContext.createMediaStreamSource(stream);
            this.audioWorkletNode = new AudioWorkletNode(this.audioContext, 'audio-stream-processor');
            
            // Handle audio data from worklet
            this.audioWorkletNode.port.onmessage = (event) => {
                const audioData = event.data;
                if (this.websocket.readyState === WebSocket.OPEN) {
                    this.websocket.send(audioData.buffer);
                    this.bytesSent += audioData.buffer.byteLength;
                    
                    // Log progress every 1000 sends
                    if (this.bytesSent % 32000 < 4096) {  // Roughly every second at 16kHz
                        console.log(`📊 Audio stats: sent ${this.bytesSent} bytes, received ${this.bytesReceived} bytes`);
                    }
                }
            };
            
            // Connect the audio processing chain
            source.connect(this.audioWorkletNode);
            
            console.log('🎙️  Audio capture started. Speak into microphone...');
            console.log('⏹️  Run debugger.stopDebugSession() to stop');
            
            this.isRecording = true;
            
        } catch (error) {
            console.error('❌ Audio capture setup failed:', error);
        }
    }

    stopDebugSession() {
        console.log('⏹️  Stopping debug session...');
        
        if (this.audioWorkletNode) {
            this.audioWorkletNode.disconnect();
            this.audioWorkletNode = null;
        }
        
        if (this.audioContext) {
            this.audioContext.close();
            this.audioContext = null;
        }
        
        if (this.websocket) {
            this.websocket.close();
            this.websocket = null;
        }
        
        console.log(`📊 Final stats: sent ${this.bytesSent} bytes, received ${this.bytesReceived} bytes`);
        console.log('✅ Debug session ended');
        
        this.isRecording = false;
    }
    
    // Helper to check current WebSocket status via Nginx
    async checkNginxProxy() {
        console.log('🔍 Testing Nginx proxy configuration...');
        
        try {
            // Test if we can reach the transcription endpoint through nginx
            const testWs = new WebSocket('ws://' + window.location.host + '/transcription');
            
            return new Promise((resolve) => {
                const timeout = setTimeout(() => {
                    console.log('⏰ Nginx proxy test timeout');
                    testWs.close();
                    resolve(false);
                }, 3000);
                
                testWs.onopen = () => {
                    console.log('✅ Nginx proxy working correctly');
                    clearTimeout(timeout);
                    testWs.close();
                    resolve(true);
                };
                
                testWs.onerror = () => {
                    console.log('❌ Nginx proxy connection failed');
                    console.log('💡 Check: docker logs nginx-container-name');
                    clearTimeout(timeout);
                    resolve(false);
                };
            });
        } catch (error) {
            console.error('❌ Nginx proxy test error:', error);
            return false;
        }
    }
}

// Auto-instantiate debugger
window.audioDebugger = new AudioDebugger();

console.log(`
🎯 WhisperFusion Audio Debugger Loaded!

Usage:
  audioDebugger.startDebugSession()  - Start full debug session
  audioDebugger.stopDebugSession()   - Stop debugging
  audioDebugger.checkNginxProxy()    - Test nginx proxy only
  audioDebugger.testWebSocketConnection() - Test WebSocket only

The debugger will check:
  ✓ Browser capabilities
  ✓ WebSocket connection
  ✓ Microphone permissions  
  ✓ Audio capture and transmission
  ✓ Nginx proxy configuration
`);

// Export for easy access
window.debugWhisperFusion = () => audioDebugger.startDebugSession();