package com.streamverse;

import javafx.application.Application;
import javafx.application.Platform;
import javafx.collections.*;
import javafx.geometry.*;
import javafx.scene.*;
import javafx.scene.control.*;
import javafx.scene.layout.*;
import javafx.scene.paint.*;
import javafx.scene.text.*;
import javafx.stage.*;
import java.util.*;

/**

 * Connects to Oracle via DatabaseHelper (JDBC).
 * Screens: Login → Register → Browse → Profile → Admin
 */
public class StreamVerseApp extends Application {

    // Shared state 
    private Stage stage;
    private int   currentUserId = -1;
    private String currentUserName = "";

    // Colour palette 
    static final String BG      = "#FFF8FA";   // blush white
    static final String SURFACE = "#FFFFFF";
    static final String ACCENT  = "#C94B8A";   // deep rose
    static final String ACCENT2 = "#8B5CF6";   // soft violet
    static final String TEXT    = "#2D1B3D";   // dark plum
    static final String MUTED   = "#9B7BAB";   // muted purple-grey
    static final String BORDER  = "#F0D4E8";   // pale pink border
    static final String CHIP    = "#F3E8FF";   // lavender chip bg
    static final String CHIP_T  = "#7C3AED";   // chip text

    // Helper: styled button 
    private Button btn(String text, boolean primary) {
        Button b = new Button(text);
        if (primary) {
            b.setStyle("-fx-background-color:" + ACCENT + ";" +
                       "-fx-text-fill:white;-fx-font-size:13px;" +
                       "-fx-font-weight:bold;-fx-background-radius:20;" +
                       "-fx-padding:8 24 8 24;-fx-cursor:hand;");
            b.setOnMouseEntered(e -> b.setStyle(b.getStyle().replace(ACCENT,"#A0356E")));
            b.setOnMouseExited(e  -> b.setStyle(b.getStyle().replace("#A0356E",ACCENT)));
        } else {
            b.setStyle("-fx-background-color:transparent;-fx-text-fill:"+ACCENT+";" +
                       "-fx-font-size:13px;-fx-border-color:"+ACCENT+";" +
                       "-fx-border-radius:20;-fx-background-radius:20;" +
                       "-fx-padding:8 24 8 24;-fx-cursor:hand;");
        }
        return b;
    }

    // Helper: styled text field 
    private TextField field(String prompt, double w) {
        TextField tf = new TextField();
        tf.setPromptText(prompt);
        tf.setPrefWidth(w);
        tf.setStyle("-fx-background-color:white;-fx-border-color:"+BORDER+";" +
                    "-fx-border-radius:10;-fx-background-radius:10;" +
                    "-fx-padding:10;-fx-font-size:13px;-fx-text-fill:"+TEXT+";");
        return tf;
    }
    private PasswordField passField(String prompt, double w) {
        PasswordField pf = new PasswordField();
        pf.setPromptText(prompt);
        pf.setPrefWidth(w);
        pf.setStyle("-fx-background-color:white;-fx-border-color:"+BORDER+";" +
                    "-fx-border-radius:10;-fx-background-radius:10;" +
                    "-fx-padding:10;-fx-font-size:13px;-fx-text-fill:"+TEXT+";");
        return pf;
    }

    //  Helper: label 
    private Label lbl(String text, int size, boolean bold, String color) {
        Label l = new Label(text);
        l.setFont(Font.font("Segoe UI", bold ? FontWeight.BOLD : FontWeight.NORMAL, size));
        l.setTextFill(Color.web(color));
        return l;
    }

    //  Helper: card pane 
    private VBox card(double w) {
        VBox v = new VBox(10);
        v.setPadding(new Insets(20));
        v.setPrefWidth(w);
        v.setStyle("-fx-background-color:white;-fx-background-radius:16;" +
                   "-fx-border-color:"+BORDER+";-fx-border-radius:16;" +
                   "-fx-effect:dropshadow(gaussian,rgba(0,0,0,0.07),10,0,0,2);");
        return v;
    }

    // ── Helper: error label
    private Label errLabel() {
        Label l = new Label();
        l.setTextFill(Color.web("#D64F4F"));
        l.setFont(Font.font("Segoe UI", 12));
        l.setWrapText(true);
        return l;
    }

    // ── Navbar
    private HBox navbar(String active) {
        HBox bar = new HBox(20);
        bar.setPadding(new Insets(14, 28, 14, 28));
        bar.setAlignment(Pos.CENTER_LEFT);
        bar.setStyle("-fx-background-color:white;-fx-border-color:"+BORDER+";-fx-border-width:0 0 1 0;");

        Label logo = lbl("✦ StreamVerse", 18, true, ACCENT);
        Region sp = new Region(); HBox.setHgrow(sp, Priority.ALWAYS);

        String[] tabs = {"Browse", "Profile", "Admin"};
        HBox nav = new HBox(4);
        for (String t : tabs) {
            Button b = new Button(t);
            boolean sel = t.equals(active);
            b.setStyle("-fx-background-color:" + (sel ? CHIP : "transparent") + ";" +
                       "-fx-text-fill:" + (sel ? CHIP_T : MUTED) + ";" +
                       "-fx-font-size:13px;-fx-background-radius:20;-fx-padding:6 16;-fx-cursor:hand;" +
                       (sel ? "-fx-font-weight:bold;" : ""));
            b.setOnAction(e -> {
                if      (t.equals("Browse"))  showBrowse();
                else if (t.equals("Profile")) showProfile();
                else                          showAdmin();
            });
            nav.getChildren().add(b);
        }

        Label user = lbl("👤 " + currentUserName, 13, false, MUTED);
        Button logout = btn("Logout", false);
        logout.setOnAction(e -> { currentUserId = -1; currentUserName = ""; showLogin(); });

        bar.getChildren().addAll(logo, sp, nav, user, logout);
        return bar;
    }

    // SCREEN 1 : LOGIN
 
    private void showLogin() {
        VBox root = new VBox();
        root.setStyle("-fx-background-color:"+BG+";");

        // Top decoration
        HBox top = new HBox();
        top.setPrefHeight(8);
        top.setStyle("-fx-background-color:linear-gradient(to right,"+ACCENT+","+ACCENT2+");");

        VBox center = new VBox(28);
        center.setAlignment(Pos.CENTER);
        center.setPadding(new Insets(60));
        VBox.setVgrow(center, Priority.ALWAYS);

        Label logo  = lbl("✦ StreamVerse", 30, true, ACCENT);
        Label tagline = lbl("Your world of stories.", 14, false, MUTED);

        VBox formCard = card(380);
        formCard.setAlignment(Pos.CENTER_LEFT);

        Label title = lbl("Welcome back ✿", 20, true, TEXT);
        Label sub   = lbl("Sign in to continue", 13, false, MUTED);

        TextField     email  = field("Email address", 340);
        PasswordField pass   = passField("Password", 340);
        Label         err    = errLabel();

        Button signIn = btn("Sign In", true);
        signIn.setPrefWidth(340);
        signIn.setOnAction(e -> {
            int uid = DatabaseHelper.login(email.getText().trim(), pass.getText());
            if (uid > 0) {
                currentUserId   = uid;
                currentUserName = DatabaseHelper.getUserInfo(uid).getOrDefault("name","User");
                showBrowse();
            } else {
                err.setText("Invalid email or password. Try: demo@streamverse.com / demo1234");
            }
        });

        Separator sep = new Separator();
        sep.setStyle("-fx-background-color:"+BORDER+";");

        HBox regRow = new HBox(8);
        regRow.setAlignment(Pos.CENTER);
        Label noAcc = lbl("Don't have an account?", 13, false, MUTED);
        Button regBtn = new Button("Create one");
        regBtn.setStyle("-fx-background-color:transparent;-fx-text-fill:"+ACCENT2+";" +
                        "-fx-font-size:13px;-fx-cursor:hand;-fx-underline:true;");
        regBtn.setOnAction(e -> showRegister());
        regRow.getChildren().addAll(noAcc, regBtn);

        formCard.getChildren().addAll(title, sub, new Label(""), email, pass, err, signIn, sep, regRow);
        center.getChildren().addAll(logo, tagline, formCard);
        root.getChildren().addAll(top, center);

        stage.setScene(new Scene(root, 900, 620));
        stage.setTitle("StreamVerse — Sign In");
        stage.show();
    }

    // SCREEN 2 : REGISTER
 
    private void showRegister() {
        VBox root = new VBox();
        root.setStyle("-fx-background-color:"+BG+";");
        HBox top = new HBox(); top.setPrefHeight(8);
        top.setStyle("-fx-background-color:linear-gradient(to right,"+ACCENT+","+ACCENT2+");");

        VBox center = new VBox(20);
        center.setAlignment(Pos.CENTER);
        center.setPadding(new Insets(50));
        VBox.setVgrow(center, Priority.ALWAYS);

        Label logo  = lbl("✦ StreamVerse", 26, true, ACCENT);
        VBox formCard = card(400);
        formCard.setAlignment(Pos.CENTER_LEFT);

        Label title = lbl("Create your account ✿", 20, true, TEXT);
        Label sub   = lbl("Join StreamVerse today", 13, false, MUTED);

        TextField     name  = field("Full name", 360);
        TextField     email = field("Email address", 360);
        TextField     phone = field("Phone (optional)", 360);
        PasswordField pass  = passField("Password (min 6 chars)", 360);
        Label err           = errLabel();

        Button regBtn = btn("Create Account", true);
        regBtn.setPrefWidth(360);
        regBtn.setOnAction(e -> {
            if (name.getText().isBlank() || email.getText().isBlank() || pass.getText().isBlank()) {
                err.setText("Name, email, and password are required."); return;
            }
            if (pass.getText().length() < 6) { err.setText("Password must be at least 6 characters."); return; }
            int uid = DatabaseHelper.register(name.getText().trim(), email.getText().trim(),
                                              phone.getText().trim(), pass.getText());
            if (uid == -2) { err.setText("Email already registered. Please sign in."); }
            else if (uid > 0) {
                currentUserId   = uid;
                currentUserName = name.getText().trim();
                // Auto-subscribe to Mobile plan
                DatabaseHelper.subscribe(uid, 1);
                showBrowse();
            } else { err.setText("Registration failed. Please try again."); }
        });

        Button back = new Button("← Back to Sign In");
        back.setStyle("-fx-background-color:transparent;-fx-text-fill:"+MUTED+";" +
                      "-fx-font-size:12px;-fx-cursor:hand;");
        back.setOnAction(e -> showLogin());

        formCard.getChildren().addAll(title, sub, new Label(""), name, email, phone, pass, err, regBtn, back);
        center.getChildren().addAll(logo, formCard);
        root.getChildren().addAll(top, center);

        stage.setScene(new Scene(root, 900, 680));
        stage.setTitle("StreamVerse — Register");
    }

    // SCREEN 3 : BROWSE
 
    private void showBrowse() {
        BorderPane root = new BorderPane();
        root.setStyle("-fx-background-color:"+BG+";");
        root.setTop(navbar("Browse"));

        // ── Filter bar ────────────────────────────────────────────────
        HBox filterBar = new HBox(12);
        filterBar.setPadding(new Insets(16, 24, 12, 24));
        filterBar.setAlignment(Pos.CENTER_LEFT);
        filterBar.setStyle("-fx-background-color:white;-fx-border-color:"+BORDER+";-fx-border-width:0 0 1 0;");

        TextField search = field("Search titles, descriptions…", 260);

        ComboBox<String> typeBox = new ComboBox<>(FXCollections.observableArrayList("All","MOVIE","SERIES"));
        typeBox.setValue("All");
        typeBox.setStyle("-fx-background-color:white;-fx-border-color:"+BORDER+";-fx-border-radius:10;-fx-background-radius:10;");

        List<String> genreList = DatabaseHelper.getAllGenres();
        ComboBox<String> genreBox = new ComboBox<>(FXCollections.observableArrayList(genreList));
        genreBox.setValue("All Genres");
        genreBox.setPrefWidth(180);
        genreBox.setStyle(typeBox.getStyle());

        Button searchBtn = btn("Search", true);

        Label count = lbl("", 12, false, MUTED);

        filterBar.getChildren().addAll(
            lbl("🎬", 16, false, ACCENT), search,
            lbl("Type:", 12, false, MUTED), typeBox,
            lbl("Genre:", 12, false, MUTED), genreBox,
            searchBtn, count);

        // ── Content grid
        FlowPane grid = new FlowPane(12, 12);
        grid.setPadding(new Insets(20, 24, 24, 24));

        ScrollPane scroll = new ScrollPane(grid);
        scroll.setFitToWidth(true);
        scroll.setStyle("-fx-background-color:"+BG+";-fx-border-color:transparent;");

        // ── Content card builder 
        // Colour palette for card thumbnails (gradient placeholders)
        String[] CARD_COLORS = {
            "#C94B8A","#8B5CF6","#EC4899","#7C3AED","#DB2777",
            "#9333EA","#A21CAF","#6D28D9","#BE185D","#5B21B6"
        };

        Runnable loadContent = () -> {
            grid.getChildren().clear();
            String q = search.getText().trim();
            String t = typeBox.getValue().equals("All") ? null : typeBox.getValue();
            String g = genreBox.getValue().equals("All Genres") ? null : genreBox.getValue();

            List<Map<String,String>> items = DatabaseHelper.getContent(q, t, g);
            count.setText(items.size() + " titles");

            for (int i = 0; i < items.size(); i++) {
                Map<String,String> item = items.get(i);
                String color = CARD_COLORS[i % CARD_COLORS.length];

                VBox card = new VBox(0);
                card.setPrefWidth(150);
                card.setStyle("-fx-background-color:white;-fx-background-radius:12;" +
                              "-fx-border-color:"+BORDER+";-fx-border-radius:12;" +
                              "-fx-cursor:hand;" +
                              "-fx-effect:dropshadow(gaussian,rgba(0,0,0,0.06),8,0,0,2);");

                // Thumbnail
                VBox thumb = new VBox();
                thumb.setPrefHeight(100);
                thumb.setPrefWidth(150);
                thumb.setAlignment(Pos.CENTER);
                thumb.setStyle("-fx-background-color:"+color+";-fx-background-radius:12 12 0 0;");

                Label typeChip = new Label(item.get("type").equals("MOVIE") ? "🎬" : "📺");
                typeChip.setFont(Font.font(24));
                Label yearLbl = lbl(item.get("year"), 11, false, "white");
                thumb.getChildren().addAll(typeChip, yearLbl);

                // Info
                VBox info = new VBox(3);
                info.setPadding(new Insets(8));
                Label titleLbl = lbl(item.get("title"), 11, true, TEXT);
                titleLbl.setWrapText(true);
                titleLbl.setMaxWidth(134);
                Label ratingLbl = lbl("★ " + item.get("rating"), 11, false, ACCENT);
                Label ageLbl = lbl(item.get("age_rating") == null ? "" : item.get("age_rating"), 10, false, MUTED);
                info.getChildren().addAll(titleLbl, ratingLbl, ageLbl);

                card.getChildren().addAll(thumb, info);

                // Click → detail popup
                final int contentId = Integer.parseInt(item.get("content_id"));
                final Map<String,String> finalItem = item;
                card.setOnMouseClicked(e -> showContentDetail(contentId, finalItem));

                // Hover effect
                card.setOnMouseEntered(e -> card.setStyle(card.getStyle()
                    .replace("rgba(0,0,0,0.06)","rgba(0,0,0,0.13)")));
                card.setOnMouseExited(e  -> card.setStyle(card.getStyle()
                    .replace("rgba(0,0,0,0.13)","rgba(0,0,0,0.06)")));

                grid.getChildren().add(card);
            }
        };

        searchBtn.setOnAction(e -> loadContent.run());
        search.setOnAction(e -> loadContent.run());
        typeBox.setOnAction(e -> loadContent.run());
        genreBox.setOnAction(e -> loadContent.run());

        VBox top2 = new VBox(); top2.getChildren().addAll(navbar("Browse"), filterBar);
        root.setTop(top2);
        root.setCenter(scroll);

        Scene scene = new Scene(root, 1100, 700);
        stage.setScene(scene);
        stage.setTitle("StreamVerse — Browse");

        // Load content after scene is shown
        Platform.runLater(loadContent);
    }

    // ── Content Detail Popup 
    private void showContentDetail(int contentId, Map<String, String> item) {
        Stage popup = new Stage();
        popup.initOwner(stage);
        popup.initModality(Modality.WINDOW_MODAL);
        popup.setTitle(item.get("title"));

        VBox root = new VBox(16);
        root.setPadding(new Insets(24));
        root.setStyle("-fx-background-color:"+BG+";");
        root.setPrefWidth(480);

        // Genre tags
        String genres = DatabaseHelper.getGenresForContent(contentId);
       FlowPane tags = new FlowPane(6, 6);
        tags.setPrefWrapLength(420);
        if (genres != null) {
            for (String g : genres.split(",")) {
                Label chip = new Label(g.trim());
                chip.setStyle("-fx-background-color:"+CHIP+";-fx-text-fill:"+CHIP_T+";" +
                              "-fx-background-radius:12;-fx-padding:3 10;-fx-font-size:11px;");
                tags.getChildren().add(chip);
            }
        }

        Label title = lbl(item.get("title"), 18, true, TEXT);
        title.setWrapText(true);

        HBox meta = new HBox(16);
        meta.getChildren().addAll(
            lbl("★ " + item.get("rating"), 13, true, ACCENT),
            lbl(item.get("year"), 13, false, MUTED),
            lbl(item.get("age_rating") == null ? "" : item.get("age_rating"), 13, false, MUTED),
            lbl(item.get("duration") + " min", 13, false, MUTED)
        );

        TextArea desc = new TextArea(item.get("description"));
        desc.setWrapText(true);
        desc.setEditable(false);
        desc.setPrefRowCount(4);
        desc.setStyle("-fx-background-color:white;-fx-border-color:"+BORDER+";" +
                      "-fx-border-radius:10;-fx-background-radius:10;-fx-font-size:13px;");

        Button watchBtn = btn("▶  Mark as Watched", true);
        watchBtn.setPrefWidth(420);
        Label watchMsg = lbl("", 12, false, "#059669");

        watchBtn.setOnAction(e -> {
            DatabaseHelper.logWatch(currentUserId, contentId);
            watchMsg.setText("✓ Added to your watch history!");
            watchBtn.setDisable(true);
        });

        Button closeBtn = btn("Close", false);
        closeBtn.setOnAction(e -> popup.close());

        root.getChildren().addAll(title, tags, meta, desc, watchBtn, watchMsg, closeBtn);

        popup.setScene(new Scene(root));
        popup.show();
    }


    // SCREEN 4 : PROFILE

    private void showProfile() {
        BorderPane root = new BorderPane();
        root.setStyle("-fx-background-color:"+BG+";");
        root.setTop(navbar("Profile"));

        ScrollPane scroll = new ScrollPane();
        scroll.setFitToWidth(true);
        scroll.setStyle("-fx-background-color:"+BG+";-fx-border-color:transparent;");

        VBox content = new VBox(20);
        content.setPadding(new Insets(24));

        // ── User info card 
        VBox userCard = card(500);
        Map<String,String> userInfo = DatabaseHelper.getUserInfo(currentUserId);
        userCard.getChildren().add(lbl("✿  My Account", 16, true, TEXT));
        for (Map.Entry<String,String> e : userInfo.entrySet()) {
            HBox row = new HBox(10);
            row.getChildren().addAll(
                lbl(cap(e.getKey()) + ":", 13, true, MUTED),
                lbl(e.getValue().isBlank() ? "—" : e.getValue(), 13, false, TEXT)
            );
            userCard.getChildren().add(row);
        }

        // ── Subscription card 
        VBox subCard = card(500);
        subCard.getChildren().add(lbl("💳  Subscription", 16, true, TEXT));
        Map<String,String> sub = DatabaseHelper.getActiveSubscription(currentUserId);

        if (sub.isEmpty()) {
            subCard.getChildren().add(lbl("No active subscription.", 13, false, MUTED));
        } else {
            // Status badge
            Label badge = new Label(sub.get("status"));
            badge.setStyle("-fx-background-color:#D1FAE5;-fx-text-fill:#065F46;" +
                           "-fx-background-radius:12;-fx-padding:3 12;-fx-font-size:11px;" +
                           "-fx-font-weight:bold;");

            GridPane grid = new GridPane();
            grid.setHgap(20); grid.setVgap(8);
            String[] keys = {"plan","price","resolution","devices","from","until","days_left"};
            String[] labels = {"Plan","Price","Quality","Devices","Valid From","Valid Until","Validity"};
            for (int i = 0; i < keys.length; i++) {
                grid.add(lbl(labels[i] + ":", 12, true, MUTED),  0, i);
                grid.add(lbl(sub.getOrDefault(keys[i], "—"),13, false, TEXT), 1, i);
            }
            subCard.getChildren().addAll(badge, grid);
        }

        // ── Upgrade plan section 
        VBox plansCard = card(700);
        plansCard.getChildren().add(lbl("⬆  Change Plan", 16, true, TEXT));
        plansCard.getChildren().add(lbl("Trigger fires automatically — end_date & payment are set by the DB!", 11, false, MUTED));

        HBox planRow = new HBox(12);
        for (Map<String,String> plan : DatabaseHelper.getAllPlans()) {
            VBox planBox = new VBox(6);
            planBox.setPadding(new Insets(14));
            planBox.setAlignment(Pos.CENTER);
            planBox.setStyle("-fx-background-color:"+CHIP+";-fx-background-radius:14;" +
                             "-fx-border-color:"+BORDER+";-fx-border-radius:14;-fx-cursor:hand;");
            planBox.setPrefWidth(120);
            planBox.getChildren().addAll(
                lbl(plan.get("plan_name"), 13, true, CHIP_T),
                lbl(plan.get("price"), 13, true, ACCENT),
                lbl(plan.get("resolution"), 11, false, MUTED),
                lbl(plan.get("devices"), 10, false, MUTED)
            );
            int planId = Integer.parseInt(plan.get("plan_id"));
            planBox.setOnMouseClicked(e -> {
                Alert confirm = new Alert(Alert.AlertType.CONFIRMATION,
                    "Switch to " + plan.get("plan_name") + " plan for " + plan.get("price") + "?\n" +
                    "The database trigger will auto-calculate your new expiry date.",
                    ButtonType.YES, ButtonType.NO);
                confirm.setTitle("Confirm Plan Change");
                confirm.showAndWait().ifPresent(bt -> {
                    if (bt == ButtonType.YES) {
                        DatabaseHelper.subscribe(currentUserId, planId);
                        showProfile(); // refresh
                    }
                });
            });
            planRow.getChildren().add(planBox);
        }
        plansCard.getChildren().add(planRow);

        // ── Watch history 
        VBox histCard = card(700);
        histCard.getChildren().add(lbl("📺  Watch History", 16, true, TEXT));

        List<Map<String,String>> history = DatabaseHelper.getWatchHistory(currentUserId);
        if (history.isEmpty()) {
            histCard.getChildren().add(lbl("Nothing watched yet. Browse content and click 'Mark as Watched'!", 12, false, MUTED));
        } else {
            TableView<Map<String,String>> table = buildHistoryTable(history);
            histCard.getChildren().add(table);
        }

        HBox columns = new HBox(20);
        columns.setAlignment(Pos.TOP_LEFT);
        columns.getChildren().addAll(
            new VBox(20, userCard, subCard),
            new VBox(20, plansCard, histCard)
        );
        content.getChildren().add(columns);
        scroll.setContent(content);
        root.setCenter(scroll);

        stage.setScene(new Scene(root, 1100, 700));
        stage.setTitle("StreamVerse — My Profile");
    }

    @SuppressWarnings("unchecked")
    private TableView<Map<String,String>> buildHistoryTable(List<Map<String,String>> data) {
        TableView<Map<String,String>> t = new TableView<>();
        t.setMaxHeight(220);
        t.setStyle("-fx-background-color:white;-fx-border-color:"+BORDER+";");
        ObservableList<Map<String,String>> obs = FXCollections.observableArrayList(data);

        String[][] cols = {{"Title","title"},{"Type","type"},{"Rating","rating"},
                           {"Date","date"},{"Progress","progress"}};
        for (String[] col : cols) {
            TableColumn<Map<String,String>,String> tc = new TableColumn<>(col[0]);
            final String key = col[1];
            tc.setCellValueFactory(c -> new javafx.beans.property.SimpleStringProperty(
                c.getValue().getOrDefault(key, "")));
            tc.setPrefWidth(col[0].equals("Title") ? 200 : 90);
            t.getColumns().add(tc);
        }
        t.setItems(obs);
        return t;
    }

    // SCREEN 5 : ADMIN ANALYTICS
  
    private void showAdmin() {
        BorderPane root = new BorderPane();
        root.setStyle("-fx-background-color:"+BG+";");
        root.setTop(navbar("Admin"));

        ScrollPane scroll = new ScrollPane();
        scroll.setFitToWidth(true);
        scroll.setStyle("-fx-background-color:"+BG+";-fx-border-color:transparent;");

        VBox content = new VBox(20);
        content.setPadding(new Insets(24));
        content.getChildren().add(lbl("📊  Admin Dashboard", 20, true, TEXT));

        // ── KPI strip (procedure call) ────────────────────────────────
        double revenue = DatabaseHelper.getTotalRevenue();
        Map<String,String> report = DatabaseHelper.getUserReport(currentUserId);

        HBox kpis = new HBox(16);
        String[][] kpiData = {
            {"Total Revenue",     "Rs. " + (int) revenue},
            {"Your Plan",         report.getOrDefault("Plan", "—")},
            {"Days Left",         report.getOrDefault("Days Left", "—")},
            {"Watch Time",        report.getOrDefault("Watch Mins", "0") + " mins"},
        };
        for (String[] kd : kpiData) {
            VBox k = new VBox(4);
            k.setPadding(new Insets(16));
            k.setAlignment(Pos.CENTER);
            k.setStyle("-fx-background-color:white;-fx-background-radius:14;" +
                       "-fx-border-color:"+BORDER+";-fx-border-radius:14;");
            k.setPrefWidth(180);
            k.getChildren().addAll(
                lbl(kd[1], 22, true, ACCENT),
                lbl(kd[0], 12, false, MUTED)
            );
            kpis.getChildren().add(k);
        }

        // ── Procedure result card ─
        VBox procCard = card(440);
        procCard.getChildren().add(lbl("🧠  Stored Procedure: get_user_report(" + currentUserId + ")", 14, true, TEXT));
        procCard.getChildren().add(lbl("Returns 5 OUT parameters via JDBC CallableStatement", 11, false, MUTED));
        for (Map.Entry<String,String> e : report.entrySet()) {
            HBox row = new HBox(10);
            row.getChildren().addAll(
                lbl(e.getKey() + ":", 12, true, MUTED),
                lbl(e.getValue() == null ? "—" : e.getValue(), 12, false, TEXT)
            );
            procCard.getChildren().add(row);
        }

        // ── Revenue by plan table 
        VBox revCard = card(440);
        revCard.getChildren().add(lbl("💰  Revenue by Plan (GROUP BY)", 14, true, TEXT));
        revCard.getChildren().add(lbl("SELECT plan_name, COUNT(*), SUM(amount) FROM PAYMENT JOIN ... GROUP BY plan_name", 10, false, MUTED));

        List<Map<String,String>> revData = DatabaseHelper.getRevenueByPlan();
        for (Map<String,String> row : revData) {
            HBox r = new HBox(20);
            r.setPadding(new Insets(6));
            r.setStyle("-fx-background-color:"+CHIP+";-fx-background-radius:8;");
            r.getChildren().addAll(
                lbl(row.get("Plan"), 13, true, CHIP_T),
                lbl(row.get("Transactions") + " subs", 12, false, MUTED),
                lbl(row.get("Revenue"), 13, true, ACCENT)
            );
            revCard.getChildren().add(r);
        }

        VBox trigCard = card(700);
        trigCard.getChildren().add(lbl("🔥  Triggers Active in the Database", 14, true, TEXT));
        String[][] triggers = {
            {"trg_calc_end_date",        "BEFORE INSERT on USER_SUBSCRIPTION",
             "Auto-calculates end_date from plan duration. No manual entry ever needed."},
            {"trg_auto_payment",         "AFTER INSERT on USER_SUBSCRIPTION",
             "Auto-inserts a PAYMENT record. Every subscription automatically logs a payment."},
            {"trg_expire_subscriptions", "BEFORE INSERT/UPDATE on USER_SUBSCRIPTION",
             "Auto-marks status=EXPIRED when end_date has passed."},
        };
        for (String[] tr : triggers) {
            VBox tBox = new VBox(3);
            tBox.setPadding(new Insets(10));
            tBox.setStyle("-fx-background-color:#FFF0F7;-fx-background-radius:10;");
            tBox.getChildren().addAll(
                lbl("▸  " + tr[0], 13, true, ACCENT),
                lbl(tr[1], 11, false, MUTED),
                lbl(tr[2], 12, false, TEXT)
            );
            trigCard.getChildren().add(tBox);
        }

        HBox row1 = new HBox(20, kpis);
        HBox row2 = new HBox(20, procCard, revCard);
        content.getChildren().addAll(row1, row2, trigCard);

        scroll.setContent(content);
        root.setCenter(scroll);

        stage.setScene(new Scene(root, 1100, 700));
        stage.setTitle("StreamVerse — Admin");
    }

    // ── Util 
    private String cap(String s) {
        if (s == null || s.isEmpty()) return s;
        return Character.toUpperCase(s.charAt(0)) + s.substring(1);
    }

    // ENTRY POINT
    
    @Override
    public void start(Stage primaryStage) {
        this.stage = primaryStage;
        stage.setMinWidth(900);
        stage.setMinHeight(600);
        showLogin();
    }

    public static void main(String[] args) {
        launch(args);
    }
}
