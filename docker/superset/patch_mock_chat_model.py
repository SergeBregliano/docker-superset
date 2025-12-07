#!/usr/bin/env python3
"""
Patch script to fix MockChatModel to be compatible with LangGraph
This fixes two issues:
1. MockChatModel doesn't inherit from BaseChatModel (Runnable)
2. MockChatModel doesn't have bind_tools method required by LangGraph
"""

import os
import sys
import re

def patch_mock_chat_model():
    """Fix MockChatModel to inherit from BaseChatModel and add bind_tools method"""
    # Try to find the file in common locations
    possible_paths = [
        "/app/.venv/lib/python3.10/site-packages/superset_chat/app/models/__init__.py",
        "/app/.venv/lib/python3.11/site-packages/superset_chat/app/models/__init__.py",
        "/app/.venv/lib/python3.12/site-packages/superset_chat/app/models/__init__.py",
    ]
    
    models_file = None
    for path in possible_paths:
        if os.path.exists(path):
            models_file = path
            break
    
    if not models_file:
        print(f"Error: File not found in any of the expected locations: {possible_paths}")
        sys.exit(1)
    
    # Read the current file
    with open(models_file, 'r') as f:
        content = f.read()
    
    # Check if already patched
    needs_abstract_methods = '_llm_type' not in content or '_generate' not in content
    needs_bind_tools = 'def bind_tools' not in content
    
    if 'from langchain_core.language_models.chat_models import BaseChatModel' in content and 'class MockChatModel(BaseChatModel)' in content:
        if not needs_abstract_methods and not needs_bind_tools:
            print("MockChatModel is already fully patched")
            return
        else:
            print("MockChatModel inherits from BaseChatModel, but needs additional methods...")
            # Continue to add missing methods
    
    # Full patch: add import and make MockChatModel inherit from BaseChatModel
    print("Applying full patch to MockChatModel...")
    
    # Step 1: Add imports for BaseChatModel and ChatResult if not present
    if 'from langchain_core.language_models.chat_models import BaseChatModel' not in content:
        # Find the import section
        import_match = re.search(r'(^import os\nfrom typing import.*?\nfrom langchain_core\.messages import.*?\n)', content, re.MULTILINE | re.DOTALL)
        if import_match:
            import_end = import_match.end()
            new_import = "from langchain_core.language_models.chat_models import BaseChatModel\n"
            content = content[:import_end] + new_import + content[import_end:]
        else:
            # Try to add after existing imports
            content = content.replace(
                'from langchain_core.messages import BaseMessage, AIMessage',
                'from langchain_core.messages import BaseMessage, AIMessage\nfrom langchain_core.language_models.chat_models import BaseChatModel'
            )
    
    # Step 2: Make MockChatModel inherit from BaseChatModel
    content = content.replace(
        'class MockChatModel:',
        'class MockChatModel(BaseChatModel):'
    )
    
    # Step 2.5: Add model_config to allow extra fields (if needed)
    # BaseChatModel uses Pydantic which doesn't allow arbitrary fields by default
    # We'll remove the self.model assignment instead
    
    # Step 3: Update __init__ to call super().__init__() and remove self.model
    # Remove self.model assignment (Pydantic doesn't allow arbitrary fields)
    content = re.sub(
        r'self\.model = "mock-model"',
        '# Removed: Pydantic model does not allow arbitrary fields',
        content
    )
    
    # Ensure super().__init__() is called
    init_pattern = r'(def __init__\(self, \*\*kwargs\):)'
    if 'super().__init__' not in content[content.find('def __init__'):content.find('def __init__')+200]:
        content = re.sub(
            init_pattern,
            r'\1\n        super().__init__(**kwargs)',
            content,
            count=1
        )
    
    # Step 4: Add abstract methods required by BaseChatModel
    # Find where to insert abstract methods (after __init__ or before bind_tools)
    abstract_methods = '''
    @property
    def _llm_type(self) -> str:
        """Return type of language model."""
        return "mock"
    
    def _generate(self, messages, stop=None, run_manager=None, **kwargs):
        """Generate a response from the model."""
        from langchain_core.outputs import ChatGeneration, ChatResult
        response = self.invoke(messages, **kwargs)
        generation = ChatGeneration(message=response)
        return ChatResult(generations=[generation], llm_output={})
'''
    
    # Check if abstract methods already exist
    if '_llm_type' not in content or '_generate' not in content:
        # Find insertion point - after __init__ method (after the comment line)
        init_end = content.find('# Removed: Pydantic model does not allow arbitrary fields')
        if init_end == -1:
            # Try alternative: find after super().__init__()
            init_end = content.find('super().__init__(**kwargs)')
        
        if init_end != -1:
            # Find the end of the __init__ method (next def or blank line)
            next_def = content.find('\n    def ', init_end)
            if next_def == -1:
                next_def = content.find('\n\nif model_type', init_end)
            if next_def != -1:
                content = content[:next_def] + abstract_methods + content[next_def:]
            else:
                # Fallback: insert before bind_tools or end of class
                insert_pos = content.find('def bind_tools', content.find('class MockChatModel'))
                if insert_pos == -1:
                    insert_pos = content.find('\n\nif model_type', content.find('class MockChatModel'))
                if insert_pos != -1:
                    content = content[:insert_pos] + abstract_methods + content[insert_pos:]
                else:
                    print("Warning: Could not find insertion point for abstract methods")
        else:
            print("Warning: Could not find __init__ method to insert abstract methods after")
    
    # Step 5: Add bind_tools method if not present
    if 'def bind_tools' not in content:
        stream_method_end = content.find('            yield AIMessageChunk(content=word + " ")')
        if stream_method_end == -1:
            # Find the end of the class
            class_end = content.find('\n\nif model_type ==', content.find('class MockChatModel'))
            if class_end == -1:
                class_end = content.find('\nif model_type ==', content.find('class MockChatModel'))
            insert_position = class_end
        else:
            insert_position = content.find('\n\nif model_type', stream_method_end)
            if insert_position == -1:
                insert_position = content.find('if model_type ==', stream_method_end)
        
        if insert_position == -1:
            print("Error: Could not find insertion point for bind_tools")
            sys.exit(1)
        
        bind_tools_method = '''
    def bind_tools(self, tools, **kwargs):
        """Bind tools to the model (required by LangGraph)"""
        # Store tools using object.__setattr__ to bypass Pydantic restrictions
        object.__setattr__(self, "bound_tools", tools)
        return self
'''
        content = content[:insert_position] + bind_tools_method + content[insert_position:]
    
    # Write the patched file
    with open(models_file, 'w') as f:
        f.write(content)
    
    print(f"Successfully patched {models_file}")
    print("Made MockChatModel inherit from BaseChatModel and added bind_tools method")

if __name__ == "__main__":
    patch_mock_chat_model()
