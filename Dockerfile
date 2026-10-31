FROM python:3.11-slim-bookworm
WORKDIR /app
ENV PYTHONUNBUFFERED=1 HF_HUB_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1 \
    MODEL_DIR=/runpod-volume/models/qwen-edit-2511 \
    LORA_PATH=/runpod-volume/loras/checkpoint.safetensors \
    OUTPUT_DIR=/runpod-volume/results OFFLOAD=1
RUN pip install --no-cache-dir torch==2.9.1 torchvision==0.24.1 --index-url https://download.pytorch.org/whl/cu128
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && pip check
COPY handler.py.in /app/temp/handler.py
CMD ["python", "-u", "/app/temp/handler.py"]
