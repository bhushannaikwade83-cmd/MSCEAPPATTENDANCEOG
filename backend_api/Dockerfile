# Dockerfile for Cloud Run deployment
FROM python:3.10-slim

WORKDIR /app

# Install system dependencies for OpenCV, TensorFlow, etc.
# Note: DeepFace uses TensorFlow (no compilation needed)
RUN apt-get update && apt-get install -y \
    libglib2.0-0 \
    libgomp1 \
    libgl1 \
    libglib2.0-0 \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN pip install --upgrade pip setuptools wheel

# Copy requirements first (for better caching)
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose port (Cloud Run sets PORT env variable)
ENV PORT=8080
EXPOSE 8080

# Set Python to unbuffered mode
ENV PYTHONUNBUFFERED=1

# Run the application
CMD exec uvicorn main:app --host 0.0.0.0 --port $PORT
