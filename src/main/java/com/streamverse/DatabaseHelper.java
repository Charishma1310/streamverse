package com.streamverse;

import java.sql.*;
import java.util.*;

/**
 * DatabaseHelper All JDBC / Oracle SQL operations for StreamVerse.
 * Change DB_URL, DB_USER, DB_PASS to match your Oracle XE setup.
 */
public class DatabaseHelper {

private static final String DB_URL  = "jdbc:oracle:thin:@localhost:1521/XEPDB1";
private static final String DB_USER = "charishma";
private static final String DB_PASS = "your_password";

    public static Connection connect() throws SQLException {
        return DriverManager.getConnection(DB_URL, DB_USER, DB_PASS);
    }

 
    // AUTH


    /** Returns the user_id if credentials match, -1 otherwise. */
    public static int login(String email, String password) {
        String sql = "SELECT user_id FROM USER_ACCOUNT WHERE LOWER(email)=LOWER(?) AND password=?";
        try (Connection c = connect(); PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setString(1, email);
            ps.setString(2, password);
            ResultSet rs = ps.executeQuery();
            if (rs.next()) return rs.getInt("user_id");
        } catch (SQLException e) { e.printStackTrace(); }
        return -1;
    }

    /** Creates a new user account. Returns user_id or -1 on failure. */
    public static int register(String name, String email, String phone, String password) {
        String sql = "INSERT INTO USER_ACCOUNT (name, email, phone, password) VALUES (?,?,?,?)";
        try (Connection c = connect(); PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setString(1, name);
            ps.setString(2, email);
            ps.setString(3, phone.isBlank() ? null : phone);
            ps.setString(4, password);
            ps.executeUpdate();
            // Retrieve the new user_id
            ResultSet rs = c.prepareStatement(
                "SELECT user_id FROM USER_ACCOUNT WHERE LOWER(email)=LOWER('" + email + "')")
                .executeQuery();
            if (rs.next()) return rs.getInt("user_id");
        } catch (SQLException e) {
            if (e.getMessage().contains("unique constraint")) return -2; // email taken
            e.printStackTrace();
        }
        return -1;
    }

    /** Returns a map of user info: name, email, phone. */
    public static Map<String, String> getUserInfo(int userId) {
        String sql = "SELECT name, email, phone FROM USER_ACCOUNT WHERE user_id=?";
        Map<String, String> info = new LinkedHashMap<>();
        try (Connection c = connect(); PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setInt(1, userId);
            ResultSet rs = ps.executeQuery();
            if (rs.next()) {
                info.put("name",  rs.getString("name"));
                info.put("email", rs.getString("email"));
                info.put("phone", rs.getString("phone") == null ? "" : rs.getString("phone"));
            }
        } catch (SQLException e) { e.printStackTrace(); }
        return info;
    }

    
    // CONTENT BROWSING
    

    /**
     * Returns content rows matching optional type and/or search query.
     * Each row: content_id, title, type, release_year, age_rating, rating_avg, description
     */
    public static List<Map<String, String>> getContent(String search, String typeFilter, String genre) {
        StringBuilder sb = new StringBuilder(
            "SELECT c.content_id, c.title, c.type, c.release_year, " +
            "c.age_rating, c.duration_min, c.rating_avg, c.description " +
            "FROM CONTENT c ");

        List<Object> params = new ArrayList<>();
        boolean hasWhere = false;

        // Genre filter via bridge table
        if (genre != null && !genre.isEmpty() && !genre.equals("All Genres")) {
            sb.append("WHERE c.content_id IN (SELECT cg.content_id FROM CONTENT_GENRE cg " +
                      "JOIN GENRE g ON cg.genre_id=g.genre_id WHERE LOWER(g.genre_name) LIKE LOWER(?)) ");
            params.add("%" + genre + "%");
            hasWhere = true;
        }

        if (typeFilter != null && !typeFilter.equals("All")) {
            sb.append(hasWhere ? "AND " : "WHERE ");
            sb.append("c.type=? ");
            params.add(typeFilter.toUpperCase());
            hasWhere = true;
        }
        if (search != null && !search.isBlank()) {
            sb.append(hasWhere ? "AND " : "WHERE ");
            sb.append("(LOWER(c.title) LIKE LOWER(?) OR LOWER(c.description) LIKE LOWER(?)) ");
            params.add("%" + search + "%");
            params.add("%" + search + "%");
        }

        sb.append("ORDER BY c.rating_avg DESC NULLS LAST FETCH FIRST 120 ROWS ONLY");

        List<Map<String, String>> result = new ArrayList<>();
        try (Connection c = connect(); PreparedStatement ps = c.prepareStatement(sb.toString())) {
            for (int i = 0; i < params.size(); i++) ps.setObject(i + 1, params.get(i));
            ResultSet rs = ps.executeQuery();
            while (rs.next()) {
                Map<String, String> row = new LinkedHashMap<>();
                row.put("content_id",  rs.getString("content_id"));
                row.put("title",       rs.getString("title"));
                row.put("type",        rs.getString("type"));
                row.put("year",        rs.getString("release_year"));
                row.put("age_rating",  rs.getString("age_rating"));
                row.put("duration",    rs.getString("duration_min"));
                row.put("rating",      rs.getString("rating_avg"));
                row.put("description", rs.getString("description"));
                result.add(row);
            }
        } catch (SQLException e) { e.printStackTrace(); }
        return result;
    }

    /** Returns genre_name list for the filter dropdown. */
    public static List<String> getAllGenres() {
        List<String> genres = new ArrayList<>();
        genres.add("All Genres");
        String sql = "SELECT genre_name FROM GENRE ORDER BY genre_name";
        try (Connection c = connect(); Statement s = c.createStatement();
             ResultSet rs = s.executeQuery(sql)) {
            while (rs.next()) genres.add(rs.getString("genre_name"));
        } catch (SQLException e) { e.printStackTrace(); }
        return genres;
    }

    /** Returns genres for a specific content_id (for detail view). */
    public static String getGenresForContent(int contentId) {
        String sql = "SELECT LISTAGG(g.genre_name, ', ') WITHIN GROUP (ORDER BY g.genre_name) AS genres " +
                     "FROM CONTENT_GENRE cg JOIN GENRE g ON cg.genre_id=g.genre_id WHERE cg.content_id=?";
        try (Connection c = connect(); PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setInt(1, contentId);
            ResultSet rs = ps.executeQuery();
            if (rs.next()) return rs.getString("genres");
        } catch (SQLException e) { e.printStackTrace(); }
        return "";
    }


    // WATCH HISTORY


    /** Inserts or updates a watch history entry. */
    public static void logWatch(int userId, int contentId) {
        // Upsert: update if exists, insert if not
        String check = "SELECT watch_id FROM WATCH_HISTORY WHERE user_id=? AND content_id=?";
        try (Connection c = connect(); PreparedStatement ps = c.prepareStatement(check)) {
            ps.setInt(1, userId); ps.setInt(2, contentId);
            ResultSet rs = ps.executeQuery();
            if (rs.next()) {
                // Update watched_on timestamp and progress
                PreparedStatement upd = c.prepareStatement(
                    "UPDATE WATCH_HISTORY SET watched_on=SYSDATE, progress_pct=100 WHERE user_id=? AND content_id=?");
                upd.setInt(1, userId); upd.setInt(2, contentId);
                upd.executeUpdate();
            } else {
                PreparedStatement ins = c.prepareStatement(
                    "INSERT INTO WATCH_HISTORY (user_id, content_id, progress_pct) VALUES (?,?,100)");
                ins.setInt(1, userId); ins.setInt(2, contentId);
                ins.executeUpdate();
            }
        } catch (SQLException e) { e.printStackTrace(); }
    }

    /** Returns the user's watch history with content details. */
    public static List<Map<String, String>> getWatchHistory(int userId) {
        String sql = "SELECT c.title, c.type, c.age_rating, wh.watched_on, wh.progress_pct " +
                     "FROM WATCH_HISTORY wh JOIN CONTENT c ON wh.content_id=c.content_id " +
                     "WHERE wh.user_id=? ORDER BY wh.watched_on DESC";
        List<Map<String, String>> result = new ArrayList<>();
        try (Connection c = connect(); PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setInt(1, userId);
            ResultSet rs = ps.executeQuery();
            while (rs.next()) {
                Map<String, String> row = new LinkedHashMap<>();
                row.put("title",    rs.getString("title"));
                row.put("type",     rs.getString("type"));
                row.put("rating",   rs.getString("age_rating"));
                row.put("date",     rs.getString("watched_on") == null ? "—" :
                                    rs.getString("watched_on").substring(0, 10));
                row.put("progress", rs.getString("progress_pct") + "%");
                result.add(row);
            }
        } catch (SQLException e) { e.printStackTrace(); }
        return result;
    }


    // SUBSCRIPTIONS  (trigger demo)


    /** Returns the active subscription info for the user. */
    public static Map<String, String> getActiveSubscription(int userId) {
        String sql = "SELECT sp.plan_name, sp.price, sp.resolution, sp.max_devices, " +
                     "us.start_date, us.end_date, us.status, " +
                     "FLOOR(us.end_date - SYSDATE) AS days_left " +
                     "FROM USER_SUBSCRIPTION us " +
                     "JOIN SUBSCRIPTION_PLAN sp ON us.plan_id=sp.plan_id " +
                     "WHERE us.user_id=? AND us.status='ACTIVE' AND ROWNUM=1";
        Map<String, String> info = new LinkedHashMap<>();
        try (Connection c = connect(); PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setInt(1, userId);
            ResultSet rs = ps.executeQuery();
            if (rs.next()) {
                info.put("plan",       rs.getString("plan_name"));
                info.put("price",      "Rs. " + (int) rs.getDouble("price") + "/mo");
                info.put("resolution", rs.getString("resolution"));
                info.put("devices",    rs.getString("max_devices") + " devices");
                info.put("from",       rs.getString("start_date") == null ? "—" :
                                       rs.getString("start_date").substring(0, 10));
                info.put("until",      rs.getString("end_date") == null ? "—" :
                                       rs.getString("end_date").substring(0, 10));
                info.put("days_left",  rs.getString("days_left") + " days left");
                info.put("status",     rs.getString("status"));
            }
        } catch (SQLException e) { e.printStackTrace(); }
        return info;
    }

    /** Returns all subscription plans. */
    public static List<Map<String, String>> getAllPlans() {
        String sql = "SELECT plan_id, plan_name, price, resolution, max_devices, description FROM SUBSCRIPTION_PLAN ORDER BY price";
        List<Map<String, String>> plans = new ArrayList<>();
        try (Connection c = connect(); Statement s = c.createStatement(); ResultSet rs = s.executeQuery(sql)) {
            while (rs.next()) {
                Map<String, String> p = new LinkedHashMap<>();
                p.put("plan_id",     rs.getString("plan_id"));
                p.put("plan_name",   rs.getString("plan_name"));
                p.put("price",       "Rs. " + (int) rs.getDouble("price"));
                p.put("resolution",  rs.getString("resolution"));
                p.put("devices",     rs.getString("max_devices") + " screen(s)");
                p.put("description", rs.getString("description"));
                plans.add(p);
            }
        } catch (SQLException e) { e.printStackTrace(); }
        return plans;
    }

    /**
     * Activates a new subscription.
     * Only inserts user_id + plan_id — the trigger fills end_date and logs payment.
     */
    public static boolean subscribe(int userId, int planId) {
        // Cancel existing active sub first
        try (Connection c = connect()) {
            PreparedStatement cancel = c.prepareStatement(
                "UPDATE USER_SUBSCRIPTION SET status='CANCELLED' WHERE user_id=? AND status='ACTIVE'");
            cancel.setInt(1, userId);
            cancel.executeUpdate();

            // INSERT — triggers fire here
            PreparedStatement ins = c.prepareStatement(
                "INSERT INTO USER_SUBSCRIPTION (user_id, plan_id) VALUES (?,?)");
            ins.setInt(1, userId);
            ins.setInt(2, planId);
            ins.executeUpdate();
            return true;
        } catch (SQLException e) { e.printStackTrace(); return false; }
    }


    // STORED PROCEDURE CALLS (viva demo)


    /** Calls get_total_revenue stored procedure. */
    public static double getTotalRevenue() {
        String sql = "{call get_total_revenue(?)}";
        try (Connection c = connect(); CallableStatement cs = c.prepareCall(sql)) {
            cs.registerOutParameter(1, Types.NUMERIC);
            cs.execute();
            return cs.getDouble(1);
        } catch (SQLException e) { e.printStackTrace(); return 0; }
    }

    /** Calls get_user_report stored procedure. Returns labelled map. */
    public static Map<String, String> getUserReport(int userId) {
        String sql = "{call get_user_report(?,?,?,?,?,?)}";
        Map<String, String> report = new LinkedHashMap<>();
        try (Connection c = connect(); CallableStatement cs = c.prepareCall(sql)) {
            cs.setInt(1, userId);
            cs.registerOutParameter(2, Types.VARCHAR);
            cs.registerOutParameter(3, Types.VARCHAR);
            cs.registerOutParameter(4, Types.VARCHAR);
            cs.registerOutParameter(5, Types.NUMERIC);
            cs.registerOutParameter(6, Types.NUMERIC);
            cs.execute();
            report.put("Name",       cs.getString(2));
            report.put("Plan",       cs.getString(3));
            report.put("Status",     cs.getString(4));
            report.put("Days Left",  cs.getString(5));
            report.put("Watch Mins", cs.getString(6));
        } catch (SQLException e) { e.printStackTrace(); }
        return report;
    }

    /** Revenue by plan — GROUP BY query used in admin dashboard. */
    public static List<Map<String, String>> getRevenueByPlan() {
        String sql = "SELECT sp.plan_name, " +
                     "COUNT(p.payment_id) AS total_transactions, " +
                     "NVL(SUM(p.amount),0) AS total_revenue " +
                     "FROM SUBSCRIPTION_PLAN sp " +
                     "LEFT JOIN USER_SUBSCRIPTION us ON sp.plan_id=us.plan_id " +
                     "LEFT JOIN PAYMENT p ON us.sub_id=p.sub_id " +
                     "GROUP BY sp.plan_name ORDER BY total_revenue DESC";
        List<Map<String, String>> result = new ArrayList<>();
        try (Connection c = connect(); Statement s = c.createStatement(); ResultSet rs = s.executeQuery(sql)) {
            while (rs.next()) {
                Map<String, String> row = new LinkedHashMap<>();
                row.put("Plan",         rs.getString("plan_name"));
                row.put("Transactions", rs.getString("total_transactions"));
                row.put("Revenue",      "Rs. " + (int) rs.getDouble("total_revenue"));
                result.add(row);
            }
        } catch (SQLException e) { e.printStackTrace(); }
        return result;
    }
}
