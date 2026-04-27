#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
"""
Simple YouTube MCP Server - A Model Context Protocol server for processing YouTube videos.
Uses FastMCP for SSE/HTTP transport support in Docker environments.
"""

import json
import os
import sys
import re
import logging
from pathlib import Path
from typing import Dict, List, Optional, Any

from fastmcp import FastMCP

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s][%(levelname)s] - %(message)s',
)
logger = logging.getLogger(__name__)

# Import YouTube dependencies with error handling
try:
    from youtube_transcript_api import YouTubeTranscriptApi, NoTranscriptFound, TranscriptsDisabled
    from googleapiclient.discovery import build
    logger.info("YouTube imports successful")
except ImportError as e:
    logger.error(f"Error importing YouTube dependencies: {e}")
    logger.error("Please install with: pip install youtube-transcript-api google-api-python-client")
    sys.exit(1)

# Initialize FastMCP server
mcp = FastMCP(name="YouTube MCP")

# Add health check endpoint for Docker
@mcp.custom_route("/health", methods=["GET"])
async def health_check(request):
    """Health check endpoint for Docker."""
    from starlette.responses import JSONResponse
    return JSONResponse({"status": "healthy", "service": "youtube-mcp"})

# Global YouTube data instance
youtube_data = None

class YouTubeData:
    """YouTube data API wrapper."""
    
    def __init__(self):
        """Initialize YouTube data API."""
        self.keyless = False
        self.api_key = None
        
        # Try to get YOUTUBE_KEY from environment
        self.api_key = os.getenv('YOUTUBE_KEY')
        
        # If not found, try to read from the file specified in YOUTUBE_KEY_FILE
        if not self.api_key:
            key_file = os.getenv('YOUTUBE_KEY_FILE')
            if key_file and os.path.exists(key_file):
                with open(key_file, 'r') as f:
                    self.api_key = f.read().strip()
        
        if not self.api_key:
            logger.warning("YOUTUBE_KEY not found. Running in KEYLESS mode (Transcripts only).")
            self.keyless = True
        else:
            try:
                self.youtube = build('youtube', 'v3', developerKey=self.api_key)
            except Exception as e:
                logger.error(f"Error building YouTube service: {e}. Falling back to KEYLESS mode.")
                self.keyless = True
    
    def get_video_metadata(self, video_id: str) -> Dict:
        """Get video metadata."""
        if self.keyless:
            return {
                'video_id': video_id,
                'title': f"Video {video_id} (Metadata Unavailable - Keyless Mode)",
                'channel_title': "Unknown",
                'description': "Metadata requires YOUTUBE_KEY. Only transcript is available.",
                'duration': "N/A",
                'published_at': "N/A",
                'view_count': 0,
                'like_count': 0,
                'comment_count': 0,
                'thumbnail_url': f"https://img.youtube.com/vi/{video_id}/default.jpg"
            }

        try:
            request = self.youtube.videos().list(
                part="snippet,contentDetails,statistics",
                id=video_id
            )
            response = request.execute()
            
            if not response['items']:
                return None
            
            video = response['items'][0]
            snippet = video['snippet']
            content_details = video['contentDetails']
            statistics = video['statistics']
            
            # Parse duration
            duration = content_details.get('duration', 'PT0S')
            hours = minutes = seconds = 0
            if 'H' in duration:
                hours = int(duration.split('H')[0].replace('PT', ''))
                duration = duration.split('H')[1]
            if 'M' in duration:
                minutes = int(duration.split('M')[0].replace('PT', ''))
                duration = duration.split('M')[1]
            if 'S' in duration:
                seconds = int(duration.split('S')[0].replace('PT', ''))
            
            duration_str = ""
            if hours > 0:
                duration_str += f"{hours}H"
            if minutes > 0:
                duration_str += f"{minutes}M"
            if seconds > 0:
                duration_str += f"{seconds}S"
            
            return {
                'video_id': video_id,
                'title': snippet.get('title', ''),
                'channel_title': snippet.get('channelTitle', ''),
                'description': snippet.get('description', ''),
                'duration': duration_str,
                'published_at': snippet.get('publishedAt', ''),
                'view_count': int(statistics.get('viewCount', 0)),
                'like_count': int(statistics.get('likeCount', 0)),
                'comment_count': int(statistics.get('commentCount', 0)),
                'thumbnail_url': snippet.get('thumbnails', {}).get('default', {}).get('url', '')
            }
        except Exception as e:
            logger.error(f"Error getting video metadata: {e}")
            return None
    
    def get_transcript(self, video_id: str) -> List:
        """Get video transcript."""
        try:
            api = YouTubeTranscriptApi()
            transcript_list = api.fetch(video_id)
            return transcript_list.to_raw_data()
        except (NoTranscriptFound, TranscriptsDisabled) as e:
            logger.warning(f"No transcript available: {e}")
            return []
        except Exception as e:
            logger.error(f"Error getting transcript: {e}")
            return []

def init_youtube_data():
    """Initialize YouTube data API."""
    global youtube_data
    if youtube_data is None:
        try:
            youtube_data = YouTubeData()
            return True
        except Exception as e:
            logger.error(f"Error initializing YouTube API: {e}")
            return False
    return True

def extract_video_id(url: str) -> str:
    """Extract YouTube video ID from URL."""
    patterns = [
        r'(?:youtube\.com\/watch\?v=|youtu\.be\/)([a-zA-Z0-9_-]{11})(?:&.*)?',
        r'youtube\.com\/embed\/([a-zA-Z0-9_-]{11})',
        r'youtube\.com\/v\/([a-zA-Z0-9_-]{11})',
        r'youtube\.com\/shorts\/([a-zA-Z0-9_-]{11})'
    ]
    
    for pattern in patterns:
        match = re.search(pattern, url)
        if match:
            return match.group(1)
    
    return ""


@mcp.tool()
async def get_video_metadata(url: str) -> Dict[str, Any]:
    """
    Get metadata for a YouTube video.
    
    Args:
        url: YouTube video URL
        
    Returns:
        Dict containing video metadata
    """
    if not init_youtube_data():
        return {"error": "Failed to initialize YouTube API"}
    
    video_id = extract_video_id(url)
    if not video_id:
        return {"error": "Invalid YouTube URL"}
    
    metadata = youtube_data.get_video_metadata(video_id)
    return metadata or {"error": "Failed to get video metadata"}


@mcp.tool()
async def get_video_transcript(url: str) -> Dict[str, Any]:
    """
    Get transcript for a YouTube video.
    
    Args:
        url: YouTube video URL
        
    Returns:
        Dict containing video transcript
    """
    if not init_youtube_data():
        return {"error": "Failed to initialize YouTube API"}
    
    video_id = extract_video_id(url)
    if not video_id:
        return {"error": "Invalid YouTube URL"}
    
    transcript = youtube_data.get_transcript(video_id)
    return {"video_id": video_id, "transcript": transcript}


@mcp.tool()
async def process_youtube_video(
    url: str,
    output_format: str = "both",
    output_path: Optional[str] = None
) -> Dict[str, Any]:
    """
    Process a YouTube video (metadata + transcript) and save results to files.
    
    Args:
        url: YouTube video URL
        output_format: Output format - 'both', 'markdown', or 'json'
        output_path: Custom output path for files (optional)
        
    Returns:
        Dict containing processing status and file paths
    """
    if not init_youtube_data():
        return {"error": "Failed to initialize YouTube API"}
    
    video_id = extract_video_id(url)
    if not video_id:
        return {"error": "Invalid YouTube URL"}
    
    # Get metadata
    metadata = youtube_data.get_video_metadata(video_id)
    if not metadata:
        metadata = {
            'title': f"Video {video_id}",
            'channel_title': "Unknown",
            'description': "Metadata unavailable",
            'duration': "N/A",
            'published_at': "N/A",
            'view_count': 0
        }
    
    # Get transcript
    transcript = youtube_data.get_transcript(video_id)

    # Determine output directory
    env_output_dir = os.environ.get("YOUTUBE_OUTPUT_DIR")
    if env_output_dir:
        output_dir = Path(env_output_dir) / video_id
    else:
        output_dir = Path("/app/youtube_output") / video_id
    
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Save metadata as JSON
    metadata_file = output_dir / f"{video_id}_metadata.json"
    with open(metadata_file, 'w') as f:
        json.dump(metadata, f, indent=2, default=str)
    
    # Save transcript as JSON
    transcript_file = output_dir / f"{video_id}_transcript.json"
    with open(transcript_file, 'w') as f:
        json.dump(transcript, f, indent=2)
    
    # Create combined markdown file
    markdown_file = output_dir / f"{video_id}_summary.md"
    with open(markdown_file, 'w') as f:
        f.write(f"# {metadata.get('title', 'Unknown Title')}\n\n")
        f.write(f"**Video ID**: {video_id}\n")
        f.write(f"**Channel**: {metadata.get('channel_title', 'N/A')}\n")
        f.write(f"**Duration**: {metadata.get('duration', 'N/A')}\n")
        f.write(f"**Views**: {metadata.get('view_count', 'N/A')}\n")
        f.write(f"**Published**: {metadata.get('published_at', 'N/A')}\n\n")
        
        f.write("## Video Description\n\n")
        f.write(f"{metadata.get('description', 'No description available')}\n\n")
        
        f.write("## Transcript\n\n")
        if transcript:
            for segment in transcript:
                f.write(f"[{segment['start']:.2f}s] {segment['text']}\n")
        else:
            f.write("No transcript available for this video.\n")
    
    return {
        "status": "success",
        "video_id": video_id,
        "metadata_file": str(metadata_file),
        "transcript_file": str(transcript_file),
        "markdown_file": str(markdown_file)
    }


def run_server():
    """Run the MCP server using FastMCP's built-in event loop handling."""
    # Determine transport based on environment
    transport = os.getenv("MCP_TRANSPORT", "stdio").lower()
    port = int(os.getenv("PORT", "8002"))
    
    # Auto-detect Docker environment
    if (os.path.exists("/.dockerenv") or os.getenv("DOCKER_CONTAINER")) and os.getenv("MCP_TRANSPORT") is None:
        transport = "sse"
        logger.info("Docker environment detected, defaulting to SSE transport")
    
    logger.info(f"Starting YouTube MCP Server with {transport} transport on port {port}...")

    try:
        if transport == "stdio":
            logger.info("Using STDIO transport")
            mcp.run(transport="stdio")
        elif transport == "sse":
            logger.info(f"Using SSE transport on 0.0.0.0:{port}")
            mcp.run(transport="sse", host="0.0.0.0", port=port)
        elif transport == "streamable-http":
            logger.info(f"Using streamable-http transport on 0.0.0.0:{port}")
            mcp.run(transport="streamable-http", host="0.0.0.0", port=port)
        else:
            raise ValueError(f"Unsupported transport: {transport}")
            
        logger.info("YouTube MCP Server stopped.")
    except Exception as e:
        logger.error(f"Error running MCP server: {str(e)}")
        sys.exit(1)


if __name__ == "__main__":
    run_server()