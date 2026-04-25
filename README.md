# streamverse

# 🎬 StreamVerse — OTT Streaming Platform

A full-stack desktop OTT platform built with **Java 17**, **JavaFX**, and **Oracle SQL** — simulating a real streaming service with user authentication, content browsing, subscription management, watch history, ratings, and an admin dashboard.

![login](screenshot1.png)
![search](screenshot2.png)
![profile](screenshot3.png)
![admin](screenshot4.png)

---

## ✨ Features

**User Side**
- Register and log in securely
- Browse movies and TV shows with filters by genre and content type
- Rate content (1–5 stars)
- View and manage watch history
- Subscribe to plans and track subscription status

**Admin Side**
- Manage subscription plans and content catalogue
- Monitor user accounts and revenue
- View analytical reports using aggregate queries

**Database**
- Fully normalized schema up to **3NF**
- Referential integrity via primary/foreign keys, UNIQUE and CHECK constraints
- **Triggers** to auto-calculate subscription validity and restrict expired-user access
- Stored procedures, sequences, views, and transaction control

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Java 17 |
| UI Framework | JavaFX 21.0.2 |
| Database | Oracle SQL (Oracle XE) |
| JDBC Driver | ojdbc8 19.3 |
| Build Tool | Maven |
| Dataset | Netflix Titles CSV (content seed data) |

---

## 🗃️ Database Schema

| Table | Description |
|-------|-------------|
| `USER_ACCOUNT` | Registered users with email, phone, status |
| `SUBSCRIPTION_PLAN` | Available plans with price and duration |
| `USER_SUBSCRIPTION` | Links users to plans with start/end dates |
| `CONTENT` | Movies and shows with type, year, language, rating |
| `GENRE` | Genre master table |
| `CONTENT_GENRE` | Many-to-many bridge between content and genres |
| `WATCH_HISTORY` | Tracks what each user has watched |
| `RATING` | User ratings (1–5) per content item |
| `PAYMENT` | Payment records per subscription |

---

## 📁 Project Structure

```
StreamVerse/
├── src/main/java/com/streamverse/
│   ├── StreamVerseApp.java     # JavaFX UI — all screens (Login, Browse, Profile, Admin)
│   └── DatabaseHelper.java     # All JDBC operations — queries, inserts, auth logic
├── StreamVerse.sql             # Full Oracle SQL script — tables, triggers, seed data
├── pom.xml                     # Maven build config
```

---

## 🚀 Getting Started

### Prerequisites

- Java 17+
- Maven 3.6+
- Oracle Database XE (or any Oracle instance)
- [ojdbc8.jar](https://www.oracle.com/database/technologies/appdev/jdbc-downloads.html) (not on Maven Central — must be installed manually)

### 1. Set Up the Database

Run the SQL script in Oracle SQL Developer or SQL*Plus:

```sql
@StreamVerse.sql
```

This creates all tables, constraints, triggers, sequences, and seeds initial data.

### 2. Configure Database Credentials

Open `DatabaseHelper.java` and update your Oracle connection details:

```java
private static final String DB_URL  = "jdbc:oracle:thin:@localhost:1521/XEPDB1";
private static final String DB_USER = "your_username";
private static final String DB_PASS = "your_password";
```

### 3. Install the JDBC Driver

```bash
mvn install:install-file -Dfile=ojdbc8.jar \
  -DgroupId=com.oracle -DartifactId=ojdbc8 \
  -Dversion=19.3 -Dpackaging=jar
```

### 4. Run the App

```bash
mvn javafx:run
```

---

## 🖥️ Screens

- **Login / Register** — Secure user authentication
- **Browse** — Search and filter content by genre, type, and keyword
- **Profile** — View subscription status, watch history, and ratings
- **Admin** — Manage users, plans, content, and view revenue reports

---

## 🔮 Possible Future Improvements

- Password hashing (currently stored as plain text)
- Video streaming integration
- Recommendation engine based on watch history
- Export reports as PDF

---

## 👥 Authors

**Kandipilli Charishma Sree**  
[GitHub](https://github.com/Charishma1310) • [LinkedIn](https://www.linkedin.com/in/charishma-sree-kandipilli-861009318/)

