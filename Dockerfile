# Use Python base image
FROM python:3.12-slim

# Set workdir
WORKDIR /app

# Copy files
COPY src/ /app

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Expose port
EXPOSE 5000

# Run the app
CMD ["python", "main.py"]
