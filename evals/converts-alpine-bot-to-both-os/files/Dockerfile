FROM alpine:3.21

WORKDIR /workspace
RUN apk --no-cache --update add python3 py3-pip tzdata

COPY requirements.txt .
RUN pip3 install --no-cache --break-system-packages -r requirements.txt

COPY src/ .
ENV TZ=Asia/Tokyo
ENV DB_PATH=/workspace/data/notes.db
VOLUME ["/workspace/data"]
ENTRYPOINT ["python3","-u","/workspace/main.py"]
