FROM python:3.12-slim
WORKDIR /app
COPY backend/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY backend /app/backend
RUN useradd --create-home translator
USER translator
EXPOSE 8000
# Single worker is mandatory for the in-memory audio hub and one-use tickets.
CMD ["uvicorn", "backend.api.app:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--ws-max-size", "500000", "--ws-max-queue", "1", "--no-access-log"]
