FROM python:3.11-slim

WORKDIR /app

# Placeholder for Jules
# Copy requirements and install Python dependencies
COPY containers/mcp-services/calendar-mcp/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy shared modules
COPY shared/ /app/shared/
ENV PYTHONPATH="${PYTHONPATH}:/app/shared"

# Copy application code
COPY containers/mcp-services/calendar-mcp/ .

CMD ["python", "app.py"]
