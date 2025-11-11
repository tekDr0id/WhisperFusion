# WhisperFusion Debug Guide

This guide helps you systematically troubleshoot the WhisperFusion setup following the fix_suggestion.txt recommendations.

## Stage 1: Stabilize Backend (Stop Crashes)

### Test 1: Minimal WebSocket Server
```bash
# Start in safe mode - only WebSocket servers, no AI models
WF_SAFE_MODE=1 docker compose -f docker-compose-safe.yml up

# Should show:
# ✅ "Starting test WebSocket servers"
# ✅ Container stays alive
```

### Test 2: Disable TensorRT Temporarily  
```bash
# Start with TensorRT disabled, CPU fallbacks only
WF_DISABLE_TRT=1 docker compose -f docker-compose-safe.yml up

# Should show:
# ✅ "Starting in CPU fallback mode"
# ✅ Container stays alive
```

### Test 3: Full TensorRT Build
```bash
# Normal startup with TensorRT (if Tests 1-2 passed)
docker compose -f docker-compose-safe.yml up

# Should show:
# ✅ "TensorRT-LLM import successful"  
# ✅ "Starting with TensorRT models"
```

## Stage 2: Verify Audio Chain

### Health Check Script
```bash
# Run health check to test all endpoints
docker exec whisperfusion-whisperfusion-1 python3 /root/health_check.py

# Should show:
# ✅ Nginx Proxy: ✅
# ✅ Transcription WS: ✅  
# ✅ Audio WS: ✅
```

### Browser Audio Debug
1. Open http://localhost:8000
2. Open DevTools Console
3. Load debug script:
   ```javascript
   // Add this script tag or paste in console
   await import('./js/debug-audio.js');
   ```
4. Run debug session:
   ```javascript
   debugWhisperFusion(); // Full test
   // OR step by step:
   audioDebugger.checkNginxProxy();
   audioDebugger.testWebSocketConnection();
   ```

## Stage 3: Layer-by-Layer Testing

### Layer A: WebSocket Only (No AI)
```bash
WF_MODE=websocket-only docker compose -f docker-compose-safe.yml up
```
Tests: Basic WebSocket communication works

### Layer B: CPU Whisper Only
```bash  
WF_MODE=whisper-only WF_DISABLE_TRT=1 docker compose -f docker-compose-safe.yml up
```
Tests: Audio → transcription works (CPU)

### Layer C: Full TensorRT Pipeline
```bash
docker compose -f docker-compose-safe.yml up  
```
Tests: Audio → TensorRT Whisper → TensorRT LLM → TTS

## Common Issues & Solutions

### Backend Keeps Crashing
- **Symptom**: Container exits after "WhisperSpeech warmup" 
- **Fix**: Use `WF_SAFE_MODE=1` first, then `WF_DISABLE_TRT=1`
- **Root Cause**: TensorRT-LLM DynamicDecodeLayer segfault

### Mic Button Does Nothing  
- **Symptom**: Click mic, no network activity in DevTools
- **Fix**: Check microphone permissions, run browser debug script
- **Root Cause**: Browser permission or WebRTC setup issue

### WebSocket Connection Fails
- **Symptom**: "WebSocket connection failed" in debug script
- **Fix**: Check docker logs, verify nginx proxy config
- **Root Cause**: Backend not listening or nginx misconfiguration  

### Audio Sent But No Response
- **Symptom**: Network shows WebSocket data sent, no response
- **Fix**: Check audio format, run health check script
- **Root Cause**: Audio format mismatch or backend processing error

## Quick Diagnosis Commands

```bash
# Check container status
docker ps

# Check backend logs
docker logs whisperfusion-whisperfusion-1

# Check nginx logs  
docker logs whisperfusion-nginx-1

# Test WebSocket from host
curl --include \
     --no-buffer \
     --header "Connection: Upgrade" \
     --header "Upgrade: websocket" \
     --header "Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==" \
     --header "Sec-WebSocket-Version: 13" \
     http://localhost:8000/transcription

# Check GPU usage (if using TensorRT)
docker exec whisperfusion-whisperfusion-1 nvidia-smi
```

## Environment Variables Reference

| Variable | Values | Purpose |
|----------|--------|---------|
| `WF_SAFE_MODE` | 0,1 | 1=Minimal WebSocket only, skip AI |
| `WF_DISABLE_TRT` | 0,1 | 1=Use CPU fallbacks, no TensorRT |
| `WF_MODE` | websocket-only, whisper-only, full | Processing layer level |
| `VERBOSE` | true,false | Enable debug logging |

## Success Criteria

✅ **Backend Stable**: Container runs >5 minutes without crashes  
✅ **WebSocket Connected**: Browser DevTools shows open WebSocket  
✅ **Audio Captured**: Debug script shows "bytes sent" increasing  
✅ **Response Received**: Debug script shows "bytes received" > 0  
✅ **End-to-End**: Speak → see transcription → hear TTS response

Follow this guide stage by stage. Don't skip to Stage 3 until Stage 1 works reliably.