# LaunchDarkly Targeting Visualization

![LaunchDarkly Targeting Visualization Demo](img/DinoGIF-small.gif)

A real-time web-based visualization tool for LaunchDarkly feature flags that shows how targeting rules affect different user contexts. This tool creates 2,000 fake user contexts and displays a grid showing whether each context receives `true` or `false` from your feature flag.

## Features

- 🎯 **Real-time visualization** of feature flag targeting across 2,000 contexts
- 🌐 **Web-based interface** with responsive design
- 🔄 **Live updates** when you change targeting rules in LaunchDarkly
- 📊 **Statistics display** showing true/false counts and percentages
- 🐳 **Docker support** for easy deployment
- 📱 **Mobile responsive** design

## What it shows

The visualization displays:
- **Green squares**: Contexts that receive `true` from your feature flag
- **Red squares**: Contexts that receive `false` from your feature flag
- **Real-time statistics**: Count and percentage of true/false evaluations
- **Multi-context targeting**: Each square represents a user with associated device and organization contexts

## Quick Start with Docker (Recommended)

### Prerequisites
- Docker and Docker Compose installed
- LaunchDarkly account with a boolean feature flag

### Setup
1. **Clone and navigate to the project**
   ```bash
   git clone <your-repo-url>
   cd ld_targeting_icons
   ```

2. **Configure environment variables**
   ```bash
   cp env.example .env
   ```
   
   Edit `.env` and add your LaunchDarkly credentials:
   ```
   SDK_KEY=sdk-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   FLAG_KEY=your-flag-key-here
   SECRET_KEY=your-secret-key-here
   ```

3. **Run with Docker Compose**
   ```bash
   docker-compose up --build
   ```

4. **Access the visualization**
   Open your browser to `http://localhost:5000`

## Manual Installation

If you prefer to run without Docker:

### Prerequisites
- Python 3.8+
- LaunchDarkly account with a boolean feature flag

### Setup
1. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

2. **Configure environment**
   ```bash
   cp env.example .env
   # Edit .env with your LaunchDarkly credentials
   ```

3. **Run the application**
   ```bash
   python app.py
   ```

4. **Access the visualization**
   Open your browser to `http://localhost:5000`

## Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `SDK_KEY` | Your LaunchDarkly Server-side SDK key | Yes |
| `FLAG_KEY` | The key of the boolean feature flag to visualize | Yes |
| `SECRET_KEY` | Flask secret key for session management | No (auto-generated) |

### Getting LaunchDarkly Credentials

1. **SDK Key**: Go to your LaunchDarkly dashboard → Account Settings → Projects → [Your Project] → Environments → [Your Environment] → Copy the SDK key
2. **Flag Key**: Create or use an existing boolean feature flag and copy its key from the flag settings

## Usage Tips

1. **Testing Percentage Rollouts**: Set your flag to a percentage rollout (e.g., 25%) and watch the visualization update in real-time
2. **Targeting Rules**: Create targeting rules based on user attributes (plan, role, metro, etc.) and see how they affect the distribution
3. **Multi-context Targeting**: The tool generates contexts with user, device, and organization attributes for comprehensive targeting testing

## Architecture

- **Backend**: Flask with Socket.IO for real-time updates
- **Frontend**: Vanilla JavaScript with WebSocket connection
- **LaunchDarkly Integration**: Python SDK with polling for flag changes
- **Containerization**: Docker with multi-stage builds and health checks

## Development

### Running in Development Mode

```bash
# Install dependencies
pip install -r requirements.txt

# Set environment variables
export FLASK_ENV=development
export FLASK_DEBUG=1

# Run the application
python app.py
```

### Docker Development

```bash
# Build and run with development settings
docker-compose up --build

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

## Troubleshooting

### Common Issues

1. **"SDK_KEY not found"**: Make sure your `.env` file exists and contains valid LaunchDarkly credentials
2. **Connection issues**: Check that port 5000 is available and not blocked by firewall
3. **Flag not updating**: Verify the FLAG_KEY matches exactly with your LaunchDarkly flag key

### Health Check

The application includes a health check endpoint at `http://localhost:5000/` that returns the main page when the service is healthy.

## Legacy Terminal Version

The original terminal-based version is still available in `main.py`. To use it:

```bash
python main.py
```

Note: The terminal version uses Unicode squares and may display differently depending on your terminal's theme settings.