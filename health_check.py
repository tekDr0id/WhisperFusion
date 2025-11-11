#!/usr/bin/env python3
"""
Health check and audio verification script for WhisperFusion
"""
import asyncio
import websockets
import json
import time
import sys
from datetime import datetime

async def test_transcription_websocket():
    """Test the transcription WebSocket endpoint"""
    try:
        uri = "ws://localhost:6006"
        print(f"🔍 Testing transcription WebSocket at {uri}")
        
        async with websockets.connect(uri, timeout=5) as websocket:
            print("✅ Connected to transcription WebSocket")
            
            # Send test audio data (empty bytes as test)
            test_data = b"test_audio_data"
            await websocket.send(test_data)
            print(f"📤 Sent test audio data ({len(test_data)} bytes)")
            
            # Wait for response
            try:
                response = await asyncio.wait_for(websocket.recv(), timeout=5)
                print(f"📥 Received response: {response[:100]}...")
                return True
            except asyncio.TimeoutError:
                print("⏰ Timeout waiting for transcription response")
                return False
                
    except Exception as e:
        print(f"❌ Transcription WebSocket test failed: {e}")
        return False

async def test_audio_websocket():
    """Test the audio (TTS) WebSocket endpoint"""
    try:
        uri = "ws://localhost:8888"
        print(f"🔍 Testing audio WebSocket at {uri}")
        
        async with websockets.connect(uri, timeout=5) as websocket:
            print("✅ Connected to audio WebSocket")
            
            # Send test TTS request
            test_request = {"text": "Hello world", "test": True}
            await websocket.send(json.dumps(test_request))
            print(f"📤 Sent test TTS request")
            
            # Wait for response
            try:
                response = await asyncio.wait_for(websocket.recv(), timeout=5)
                print(f"📥 Received audio response: {response[:100]}...")
                return True
            except asyncio.TimeoutError:
                print("⏰ Timeout waiting for audio response")
                return False
                
    except Exception as e:
        print(f"❌ Audio WebSocket test failed: {e}")
        return False

def check_nginx_proxy():
    """Check if nginx is properly proxying requests"""
    import requests
    try:
        print("🔍 Testing nginx proxy endpoints...")
        
        # Test main page
        response = requests.get("http://localhost:8000", timeout=5)
        if response.status_code == 200:
            print("✅ Main page accessible through nginx")
        else:
            print(f"⚠️  Main page returned status {response.status_code}")
            
        return True
    except Exception as e:
        print(f"❌ Nginx proxy test failed: {e}")
        return False

async def full_audio_chain_test():
    """Test the complete audio chain: browser -> nginx -> backend"""
    print("\n🎯 Testing complete audio chain...")
    
    # Test nginx proxy
    nginx_ok = check_nginx_proxy()
    
    # Test backend WebSockets
    transcription_ok = await test_transcription_websocket()
    audio_ok = await test_audio_websocket()
    
    print(f"\n📊 Test Results:")
    print(f"   Nginx Proxy: {'✅' if nginx_ok else '❌'}")
    print(f"   Transcription WS: {'✅' if transcription_ok else '❌'}")
    print(f"   Audio WS: {'✅' if audio_ok else '❌'}")
    
    if nginx_ok and transcription_ok and audio_ok:
        print("🎉 All tests passed! Audio chain is ready.")
        return True
    else:
        print("💥 Some tests failed. Check the logs above.")
        return False

if __name__ == "__main__":
    print("🏥 WhisperFusion Health Check")
    print("=" * 50)
    
    # Run the tests
    try:
        result = asyncio.run(full_audio_chain_test())
        sys.exit(0 if result else 1)
    except KeyboardInterrupt:
        print("\n⏹️  Test interrupted")
        sys.exit(1)
    except Exception as e:
        print(f"\n💥 Test suite failed: {e}")
        sys.exit(1)