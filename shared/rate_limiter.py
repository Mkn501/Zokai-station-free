
import os
import time
import functools
import logging
import redis
from contextlib import contextmanager

# Configure logging
logger = logging.getLogger("rate_limiter")
if not logger.handlers:
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter('[RateLimit] %(message)s'))
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

# Global Redis client
_redis_client = None

def get_redis_client():
    global _redis_client
    if _redis_client is None:
        redis_host = os.environ.get('REDIS_HOST', 'redis')
        redis_port = int(os.environ.get('REDIS_PORT', 6379))
        redis_password = os.environ.get('REDIS_PASSWORD')
        if not redis_password:
            logger.warning("REDIS_PASSWORD not set — rate limiting disabled (fail-open)")
            return None
        try:
            _redis_client = redis.Redis(
                host=redis_host, 
                port=redis_port, 
                password=redis_password,
                decode_responses=True,
                socket_timeout=1
            )
            _redis_client.ping()
        except Exception as e:
            logger.error(f"Failed to connect to Redis: {e}")
            _redis_client = None
    return _redis_client

class FastMCPError(Exception):
    """Custom error class that FastMCP/Stdio should catch/display."""
    pass

def rate_limit(limit=100, period=60):
    """
    Decorator to enforce rate limits on MCP tools.
    
    Args:
        limit (int): Number of requests allowed.
        period (int): Time period in seconds.
    """
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            r = get_redis_client()
            
            # Fail-open if Redis is down logic
            if not r:
                return func(*args, **kwargs)

            try:
                # Identity Resolution
                # In Stdio/Docker/Workstation, we treat the 'user' as single-tenant 'workstation-user'
                # For more complex auth, we'd inspect contextvar or args
                client_id = "workstation-user"
                
                # Key construction: "ratelimit:<service>:<func>:<id>"
                # We assume service name is env var or generic
                service_name = os.environ.get("mcp_service_name", "unknown-service")
                func_name = func.__name__
                key = f"ratelimit:{service_name}:{func_name}:{client_id}"
                
                # Check Limit (Token Bucket / Sliding Window approximation)
                # Using simple fixed window for simplicity: current_minute
                current_window = int(time.time() / period)
                window_key = f"{key}:{current_window}"
                
                # Atomic increment
                current_count = r.incr(window_key)
                
                # Set expiry if new key
                if current_count == 1:
                    r.expire(window_key, period + 10)
                
                if current_count > limit:
                    logger.warning(f"Rate limit exceeded for {key}: {current_count}/{limit}")
                    # In FastMCP, raising an exception returns a user-visible error
                    raise FastMCPError(f"Rate limit exceeded. Try again in {period} seconds.")
                
                return func(*args, **kwargs)
                
            except FastMCPError:
                raise
            except Exception as e:
                # Fail-open on internal logic errors to prevent blocking usage
                logger.error(f"Rate limiting logic failed: {e}")
                return func(*args, **kwargs)
                
        return wrapper
    return decorator
