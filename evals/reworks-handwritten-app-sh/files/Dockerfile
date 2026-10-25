FROM alpine:3.21
WORKDIR /app
RUN apk add --no-cache python3 py3-pip
COPY requirements.txt .
RUN pip3 install --no-cache --break-system-packages -r requirements.txt
COPY src/ .
ENV STORE=/data/clips.json
VOLUME ["/data"]
EXPOSE 7070
CMD ["python3", "-u", "server.py"]
