from flask import Flask, render_template, jsonify, request
from flask_socketio import SocketIO, emit
from dotenv import load_dotenv
import json
import ldclient
from ldclient.config import Config
import os
import secrets
import threading
import time
import shutil
from werkzeug.utils import secure_filename
from PIL import Image
from utils.create_context import create_multi_context

# Load environment variables
load_dotenv()

app = Flask(__name__, static_folder='static')
# Flask session secret: generated per boot when not supplied; nothing persists across restarts anyway.
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY') or secrets.token_hex(32)
socketio = SocketIO(app, cors_allowed_origins="*")

# LaunchDarkly configuration
sdk_key = os.environ.get('SDK_KEY')
feature_flag_key = os.environ.get('FLAG_KEY')

if sdk_key:
    ldclient.set_config(Config(sdk_key, send_events=False))
else:
    print("Warning: SDK_KEY not found in environment variables")

# Global variables
contexts_data = []
current_state = []
beta_selected_indices = set()

# Configuration for file uploads
UPLOAD_FOLDER = 'static/images'
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024  # 16MB max file size

def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def create_contexts():
    """Create fake contexts for visualization"""
    global beta_selected_indices
    num_contexts = 2000
    contexts_array = []
    for i in range(num_contexts):
        is_beta = i in beta_selected_indices
        context = create_multi_context(is_beta)
        contexts_array.append(context)
    return contexts_array

def recreate_contexts():
    """Recreate contexts when beta selection changes"""
    global contexts_data, current_state
    contexts_data = create_contexts()
    current_state = evaluate_contexts(contexts_data)
    # Emit update to all clients
    socketio.emit('flag_update', {'data': current_state})

def evaluate_contexts(contexts):
    """Evaluate all contexts against the feature flag"""
    if not sdk_key or not feature_flag_key:
        # Return dummy data if no LaunchDarkly config
        return [i % 2 == 0 for i in range(len(contexts))]
    
    results = []
    for context in contexts:
        try:
            feature = ldclient.get().variation(feature_flag_key, context, False)
            results.append(feature)
        except Exception as e:
            print(f"Error evaluating context: {e}")
            results.append(False)
    return results

def background_polling():
    """Background thread to poll for flag changes"""
    global current_state
    
    while True:
        try:
            new_state = evaluate_contexts(contexts_data)
            if new_state != current_state:
                current_state = new_state
                # Emit the new state to all connected clients
                socketio.emit('flag_update', {'data': current_state})
        except Exception as e:
            print(f"Error in background polling: {e}")
        
        time.sleep(0.5)  # Poll every 500ms

@app.route('/healthz')
def healthz():
    # Demo Depot health check: cheap, no LaunchDarkly call
    return 'ok', 200, {'Content-Type': 'text/plain'}


@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/initial-data')
def get_initial_data():
    """Get initial flag evaluation data"""
    global contexts_data, current_state
    
    if not contexts_data:
        contexts_data = create_contexts()
        current_state = evaluate_contexts(contexts_data)
    
    return jsonify({
        'data': current_state,
        'total_contexts': len(contexts_data),
        'flag_key': feature_flag_key or 'Not configured'
    })

@socketio.on('connect')
def handle_connect():
    print('Client connected')
    # Send initial data to the newly connected client
    emit('flag_update', {'data': current_state})

@socketio.on('disconnect')
def handle_disconnect():
    print('Client disconnected')

# Admin API routes
@app.route('/api/upload-image', methods=['POST'])
def upload_image():
    """Handle image upload"""
    try:
        if 'image' not in request.files:
            return jsonify({'success': False, 'error': 'No image file provided'})
        
        file = request.files['image']
        if file.filename == '':
            return jsonify({'success': False, 'error': 'No file selected'})
        
        if file and allowed_file(file.filename):
            # Create upload directory if it doesn't exist
            os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
            
            # Save the uploaded file as reveal-image.png (replacing the current one)
            filename = 'reveal-image.png'
            filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
            
            # Process the image to ensure it's the right format
            image = Image.open(file.stream)
            
            # Convert to RGB if necessary (for PNG with transparency)
            if image.mode in ('RGBA', 'LA', 'P'):
                # Create a white background
                background = Image.new('RGB', image.size, (255, 255, 255))
                if image.mode == 'P':
                    image = image.convert('RGBA')
                background.paste(image, mask=image.split()[-1] if image.mode == 'RGBA' else None)
                image = background
            
            # Resize to recommended dimensions if needed
            # The grid is 40x50 squares at 15px each = 600x750px
            target_size = (600, 750)
            if image.size != target_size:
                image = image.resize(target_size, Image.Resampling.LANCZOS)
            
            # Save as PNG
            image.save(filepath, 'PNG', optimize=True)
            
            return jsonify({'success': True, 'message': 'Image uploaded successfully'})
        else:
            return jsonify({'success': False, 'error': 'Invalid file type. Please use PNG, JPG, or GIF.'})
    
    except Exception as e:
        print(f"Error uploading image: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/reset-image', methods=['POST'])
def reset_image():
    """Reset to default dino image"""
    try:
        # Path to the current image
        current_image = os.path.join(app.config['UPLOAD_FOLDER'], 'reveal-image.png')
        
        # Check if there's a backup of the original dino image
        backup_image = os.path.join(app.config['UPLOAD_FOLDER'], 'reveal-image-original.png')
        
        if os.path.exists(backup_image):
            # Restore from backup
            shutil.copy2(backup_image, current_image)
        else:
            # If no backup exists, we'll need to handle this case
            # For now, just return an error
            return jsonify({'success': False, 'error': 'Original dino image not found. Please upload a new image.'})
        
        return jsonify({'success': True, 'message': 'Image reset to default dino'})
    
    except Exception as e:
        print(f"Error resetting image: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/set-beta-selection', methods=['POST'])
def set_beta_selection():
    """Set which contexts are beta users"""
    try:
        global beta_selected_indices
        data = request.get_json()
        selected_indices = data.get('selected_indices', [])
        
        # Update the global beta selection
        beta_selected_indices = set(selected_indices)
        
        # Recreate contexts with new beta selection
        recreate_contexts()
        
        return jsonify({'success': True})
    
    except Exception as e:
        print(f"Error setting beta selection: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/clear-beta-selection', methods=['POST'])
def clear_beta_selection():
    """Clear beta user selection"""
    try:
        global beta_selected_indices
        beta_selected_indices = set()
        
        # Recreate contexts without beta selection
        recreate_contexts()
        
        return jsonify({'success': True})
    
    except Exception as e:
        print(f"Error clearing beta selection: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/get-beta-selection', methods=['GET'])
def get_beta_selection():
    """Get current beta user selection"""
    try:
        global beta_selected_indices
        return jsonify({'success': True, 'selected_indices': list(beta_selected_indices)})
    
    except Exception as e:
        print(f"Error getting beta selection: {e}")
        return jsonify({'success': False, 'error': str(e)})

if __name__ == '__main__':
    # Initialize contexts
    contexts_data = create_contexts()
    current_state = evaluate_contexts(contexts_data)
    
    # Start background polling thread
    polling_thread = threading.Thread(target=background_polling, daemon=True)
    polling_thread.start()
    
    # Run the Flask app
    socketio.run(app, host='0.0.0.0', port=5000, debug=False, allow_unsafe_werkzeug=True)

