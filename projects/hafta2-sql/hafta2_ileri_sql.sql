-- ============================================================
-- HAFTA 2: İleri SQL ve Execution Plan Okuryazarlığı
-- Konu: Window Functions, CTE, Recursive CTE, Index Optimizasyonu
-- Veri seti: orders (e-ticaret sipariş verisi, ~50.000 satır)
-- ============================================================


-- ============================================================
-- BÖLÜM 1: WINDOW FUNCTIONS
-- ============================================================

-- Sorgu 1a: GROUP BY ile toplam (karşılaştırma amaçlı)
-- Not: Bu, her müşteri için TEK satır döner, sipariş detayını kaybederiz.
SELECT customer_id, SUM(amount) AS toplam_harcama
FROM orders
GROUP BY customer_id
ORDER BY customer_id;


-- Sorgu 1b: SUM() OVER (PARTITION BY) — Window function versiyonu
-- Neden bu şekilde: Her siparişi tek tek görürken, aynı zamanda o müşterinin
-- toplam harcamasını da her satıra ekliyoruz. GROUP BY'ın aksine detay kaybolmuyor.
SELECT
    order_id,
    customer_id,
    amount,
    SUM(amount) OVER (PARTITION BY customer_id) AS musteri_toplam_harcama
FROM orders
ORDER BY customer_id, order_id;


-- Sorgu 2: ROW_NUMBER() — Her müşterinin siparişlerini sıralama
-- Neden bu şekilde: "Bu müşterinin kaçıncı siparişi" bilgisini üretmek için.
-- ROW_NUMBER her satıra MUTLAKA benzersiz bir sıra verir (eşitlik olsa bile).
SELECT
    order_id,
    customer_id,
    order_date,
    amount,
    ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date) AS siparis_sirasi
FROM orders
ORDER BY customer_id, order_date;


-- Sorgu 3: RANK() — Kategori içinde en pahalı siparişleri sıralama
-- Neden bu şekilde: RANK, ROW_NUMBER'dan farklı olarak eşit değerlere aynı sırayı
-- verir ve bir sonraki sırayı atlar (örn. 1, 1, 3). Bu, "sıralamada eşitlik olabilir"
-- durumlarında (burada: aynı tutarlı siparişler) daha doğru bir semantik taşır.
SELECT
    order_id,
    category,
    amount,
    RANK() OVER (PARTITION BY category ORDER BY amount DESC) AS kategori_sirasi
FROM orders
ORDER BY category, kategori_sirasi;


-- Sorgu 4: LAG() — Bir önceki siparişle karşılaştırma
-- Neden bu şekilde: Müşterinin harcama trendini (arttı mı azaldı mı) satır satır
-- takip etmek için. İlk siparişte LAG null döner çünkü "önceki" sipariş yok —
-- bu beklenen ve doğru bir davranıştır, hataya işaret etmez.
SELECT
    order_id,
    customer_id,
    order_date,
    amount,
    LAG(amount) OVER (PARTITION BY customer_id ORDER BY order_date) AS onceki_siparis_tutari,
    amount - LAG(amount) OVER (PARTITION BY customer_id ORDER BY order_date) AS fark
FROM orders
ORDER BY customer_id, order_date;


-- Sorgu 5: LEAD() — Bir sonraki siparişe bakma
-- Neden bu şekilde: LAG'in tersi — "bu siparişten sonra müşteri ne kadar harcadı"
-- sorusuna cevap verir. Örn. bir kampanyanın sonraki satın almaya etkisini
-- incelemek için kullanılabilir.
SELECT
    order_id,
    customer_id,
    order_date,
    amount,
    LEAD(amount) OVER (PARTITION BY customer_id ORDER BY order_date) AS sonraki_siparis_tutari
FROM orders
ORDER BY customer_id, order_date;


-- ============================================================
-- BÖLÜM 2: CTE (Common Table Expression)
-- ============================================================

-- Sorgu 6: CTE ile kategori ortalamasının üzerindeki siparişleri bulma
-- Neden bu şekilde: Aynı hesabı (AVG(amount)) bir alt sorgu olarak JOIN içine
-- gömmek yerine, CTE ile isimlendirilmiş, okunabilir bir ara adım oluşturuyoruz.
-- Bu, özellikle sorgu büyüdükçe okunabilirliği ciddi şekilde artırır.
WITH kategori_ortalamalari AS (
    SELECT
        category,
        AVG(amount) AS ortalama_tutar
    FROM orders
    GROUP BY category
)
SELECT
    o.order_id,
    o.category,
    o.amount,
    k.ortalama_tutar,
    o.amount - k.ortalama_tutar AS ortalamadan_fark
FROM orders o
JOIN kategori_ortalamalari k ON o.category = k.category
WHERE o.amount > k.ortalama_tutar
ORDER BY o.category, o.amount DESC;


-- Sorgu 7: Recursive CTE — kendi kendini referans eden CTE
-- Neden bu şekilde: Hiyerarşik veya sıralı veri üretmek/dolaşmak için kullanılır.
-- Burada en yalın haliyle bir sayı dizisi üretiyoruz. UNION ALL'ın üstü başlangıç
-- noktası, altı ise "öncekinin üzerine işlem yap, tekrar et" mantığı.
-- KRİTİK: WHERE n < 5 durma koşulu olmazsa sonsuz döngüye girer.
WITH RECURSIVE sayi_dizisi AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1
    FROM sayi_dizisi
    WHERE n < 5
)
SELECT * FROM sayi_dizisi;


-- ============================================================
-- BÖLÜM 3: EXECUTION PLAN OKUMA VE INDEX OPTİMİZASYONU
-- ============================================================

-- Sorgu 8: Index oluşturmadan önce — EXPLAIN ANALYZE ile plan inceleme
-- Neden bu şekilde: Sorgu yazmadan önce, PostgreSQL'in bu sorguyu nasıl
-- çalıştıracağını görmek için. Küçük tabloda (15 satır) planner "Seq Scan"
-- (tüm tabloyu tarama) seçer çünkü index kullanmanın maliyeti, tarama
-- maliyetinden daha yüksektir.
EXPLAIN ANALYZE
SELECT * FROM orders WHERE customer_id = 3;


-- Index oluşturma
CREATE INDEX idx_orders_customer_id ON orders(customer_id);


-- Sorgu 9: Index sonrası, büyütülmüş tabloda (~50.000 satır) plan karşılaştırması
-- Neden bu şekilde: Index'in gerçek faydası tablo büyüdükçe ortaya çıkar.
-- 50.000 satırlık tabloda planner artık "Bitmap Index Scan" kullanmayı tercih
-- eder çünkü index üzerinden direkt eşleşen satırlara gitmek, tüm tabloyu
-- taramaktan çok daha ucuzdur.
EXPLAIN ANALYZE
SELECT * FROM orders WHERE customer_id = 3;


-- Sorgu 10: Index'i devre dışı bırakıp gerçek Seq Scan maliyetini ölçme
-- Neden bu şekilde: Index'in gerçek faydasını sayısal olarak kanıtlamak için,
-- planner'ı geçici olarak index kullanmamaya zorluyoruz. Bu, "index var ama
-- kullanılıyor mu" sorusunu doğrudan test etmenin en net yolu.
SET enable_indexscan = off;
SET enable_bitmapscan = off;

EXPLAIN ANALYZE
SELECT * FROM orders WHERE customer_id = 3;

-- Ayarları normale döndürmek KRİTİK — unutulursa oturum boyunca index
-- görmezden gelinmeye devam eder.
SET enable_indexscan = on;
SET enable_bitmapscan = on;


-- ============================================================
-- SONUÇ: ÖNCE/SONRA KARŞILAŞTIRMASI (Gerçek Ölçüm)
-- ============================================================
--
-- Sorgu: SELECT * FROM orders WHERE customer_id = 3;
-- Tablo boyutu: ~50.015 satır
--
-- | Yöntem                          | Execution Time | Taranan Satır         |
-- |----------------------------------|-----------------|------------------------|
-- | Seq Scan (index kapalı)          | 7.285 ms        | 50.015 (tümü)          |
-- | Bitmap Index Scan (index açık)   | 0.546 ms        | 55 (sadece eşleşen)    |
--
-- SONUÇ: Index kullanımı bu sorguda yaklaşık 13 KAT hız artışı sağladı.
-- Tabloda 15 satır varken index'in hiçbir faydası yoktu (planner bilerek
-- Seq Scan seçti) — bu, "index eklemek her zaman hızlandırır" varsayımının
-- YANLIŞ olduğunu gösteren somut bir kanıt. Index'in değeri veri hacmiyle
-- birlikte ortaya çıkar.
-- ============================================================
