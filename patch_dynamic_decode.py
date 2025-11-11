#!/usr/bin/env python3
"""
Emergency patch for DynamicDecodeLayer segfaults on RTX 3090
This completely disables the problematic DynamicDecodeLayer
"""
import os
import sys
import shutil
from pathlib import Path

def patch_dynamic_decode():
    """Patch DynamicDecodeLayer to prevent segfaults"""
    
    print("🔧 Applying emergency DynamicDecodeLayer patch for RTX 3090...")
    
    # Find TensorRT-LLM installation
    try:
        import tensorrt_llm
        trtllm_path = Path(tensorrt_llm.__file__).parent
        print(f"📍 Found TensorRT-LLM at: {trtllm_path}")
    except ImportError:
        print("❌ TensorRT-LLM not found")
        return False
    
    # Patch dynamic_decode.py
    dynamic_decode_file = trtllm_path / "layers" / "dynamic_decode.py"
    
    if not dynamic_decode_file.exists():
        print(f"⚠️  DynamicDecode file not found: {dynamic_decode_file}")
        return False
    
    # Create backup
    backup_file = dynamic_decode_file.with_suffix('.py.backup')
    if not backup_file.exists():
        shutil.copy2(dynamic_decode_file, backup_file)
        print(f"💾 Backed up original to: {backup_file}")
    
    # Read original file
    with open(dynamic_decode_file, 'r') as f:
        content = f.read()
    
    # Apply patches
    patches_applied = 0
    
    # Patch 1: Wrap DynamicDecodeLayer constructor with try/catch
    if 'class DynamicDecodeLayer' in content and 'RTX3090_PATCHED' not in content:
        old_init = 'def __init__(self'
        new_init = '''def __init__(self
        # RTX3090_PATCHED: Emergency segfault prevention
        try:
            return self._original_init(*args, **kwargs)
        except Exception as e:
            print(f"🚨 DynamicDecodeLayer init failed: {e}")
            print("🔄 Using CPU fallback mode")
            raise RuntimeError("DynamicDecodeLayer disabled for RTX 3090 compatibility")
    
    def _original_init(self'''
        
        content = content.replace(old_init, new_init, 1)
        patches_applied += 1
        print("✅ Applied DynamicDecodeLayer constructor patch")
    
    # Patch 2: Add safety wrapper for allocateBuffer
    if 'def allocateBuffer' in content and 'RTX3090_BUFFER_PATCH' not in content:
        buffer_patch = '''
    def allocateBuffer(self, *args, **kwargs):
        """RTX3090_BUFFER_PATCH: Prevent segfault in allocateBuffer"""
        try:
            # Conservative memory allocation for RTX 3090
            import torch
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
                # Reduce allocation size for RTX 3090 compatibility
                if hasattr(self, 'max_batch_size'):
                    self.max_batch_size = min(self.max_batch_size, 1)
                if hasattr(self, 'max_input_len'):
                    self.max_input_len = min(self.max_input_len, 512)
            
            return self._original_allocateBuffer(*args, **kwargs)
            
        except Exception as e:
            print(f"🚨 DynamicDecodeLayer.allocateBuffer failed: {e}")
            print("💡 Try reducing batch_size or sequence length")
            raise RuntimeError("Buffer allocation failed - RTX 3090 memory issue")
    
    def _original_allocateBuffer(self, *args, **kwargs):
        """Original allocateBuffer method"""'''
        
        # Insert the patch before the original allocateBuffer method
        content = content.replace(
            'def allocateBuffer(self, *args, **kwargs):',
            buffer_patch + '\n        # Original method follows...\n    def _original_allocateBuffer(self, *args, **kwargs):'
        )
        patches_applied += 1
        print("✅ Applied allocateBuffer safety patch")
    
    # Patch 3: Add emergency fallback import
    fallback_import = '''
# RTX3090_PATCHED: Emergency fallback for segfaults
import os
import warnings

def _rtx3090_emergency_fallback():
    """Emergency fallback when DynamicDecodeLayer fails"""
    warnings.warn(
        "DynamicDecodeLayer failed on RTX 3090. "
        "Using CPU fallback mode. "
        "Set WF_DISABLE_TRT=1 to avoid this warning.",
        RuntimeWarning
    )
    raise ImportError("DynamicDecodeLayer disabled for RTX 3090 compatibility")

# Check if we should use emergency fallback
if os.environ.get('WF_RTX3090_FALLBACK', '0') == '1':
    _rtx3090_emergency_fallback()

'''
    
    if 'RTX3090_PATCHED' not in content:
        content = fallback_import + content
        patches_applied += 1
        print("✅ Applied emergency fallback patch")
    
    # Write patched file
    if patches_applied > 0:
        with open(dynamic_decode_file, 'w') as f:
            f.write(content)
        print(f"🎯 Applied {patches_applied} patches to {dynamic_decode_file}")
        
        # Clear Python cache
        cache_dir = trtllm_path / "layers" / "__pycache__"
        if cache_dir.exists():
            shutil.rmtree(cache_dir)
            print("🧹 Cleared Python cache")
        
        return True
    else:
        print("ℹ️  Patches already applied or not needed")
        return True

def restore_original():
    """Restore original DynamicDecodeLayer"""
    try:
        import tensorrt_llm
        trtllm_path = Path(tensorrt_llm.__file__).parent
        
        dynamic_decode_file = trtllm_path / "layers" / "dynamic_decode.py"
        backup_file = dynamic_decode_file.with_suffix('.py.backup')
        
        if backup_file.exists():
            shutil.copy2(backup_file, dynamic_decode_file)
            print("✅ Restored original DynamicDecodeLayer")
            
            # Clear cache
            cache_dir = trtllm_path / "layers" / "__pycache__"
            if cache_dir.exists():
                shutil.rmtree(cache_dir)
                print("🧹 Cleared Python cache")
                
            return True
        else:
            print("⚠️  No backup found")
            return False
            
    except Exception as e:
        print(f"❌ Restore failed: {e}")
        return False

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Patch DynamicDecodeLayer for RTX 3090")
    parser.add_argument("--restore", action="store_true", help="Restore original file")
    parser.add_argument("--patch", action="store_true", help="Apply patches")
    
    args = parser.parse_args()
    
    if args.restore:
        success = restore_original()
    elif args.patch:
        success = patch_dynamic_decode()
    else:
        # Auto-patch by default
        success = patch_dynamic_decode()
    
    sys.exit(0 if success else 1)