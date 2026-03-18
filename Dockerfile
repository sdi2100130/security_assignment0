FROM python:3.9-slim

#change wroking dir
WORKDIR /app

#create a unique index.html
RUN echo "<h1>Hello from sdi2100130"> index.html

#open port 8000
EXPOSE 8000

#run in the pythons server
CMD ["python", "-m", "http.server", "8000"]
