# Running SonarQube Locally with Docker and PostgreSQL

## What is SonarQube?

SonarQube is an open-source platform that is used to measure and analyze the quality of source code. It provides a comprehensive set of features for code analysis, including:

- Detecting bugs, code smells, and security vulnerabilities
- Tracking technical debt
- Enforcing coding standards
- Providing extensive reporting and dashboards

SonarQube supports a wide range of programming languages, including Java, JavaScript, C/C++, C#, PHP, and many others. It can be integrated with various development tools and continuous integration (CI) pipelines to ensure that code quality is maintained throughout the software development lifecycle.

## Running SonarQube Locally with Docker and PostgreSQL

- Pull the sonarQube image from Dockerhub with the following command
```bash
docker pull sonarqube
```
- Pull and run the PostgreSQL container  with the following command
```bash
docker run -d --name sonarqube-db -p 5432:5432 -e POSTGRES_USER=sonar -e POSTGRES_PASSWORD=sonar -e POSTGRES_DB=sonarqube postgres:alpine
```
*Make sure to change the port mapping if you have conflicts*

- Run SonarQube with the following command which utilizes the database instance running already
```bash
docker run --name sonarqube -p 9000:9000 -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true --link sonarqube-db:db -e SONAR_JDBC_URL=jdbc:postgresql://db:5432/sonarqube -e SONAR_JDBC_USERNAME=sonar -e SONAR_JDBC_PASSWORD=sonar sonarqube
```
*Make sure to change the port mapping if you have conflicts*

- That said, you have SonarQube up and running and can be accessible on your host machine (http://localhost:9000)

For more information [click here](https://www.sonarsource.com/products/sonarqube/)