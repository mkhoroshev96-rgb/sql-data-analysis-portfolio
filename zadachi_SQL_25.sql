-- 143. «Топ-3 клієнтів за сумою покупок»

SELECT customer_id 
       ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id
ORDER BY sum_chek DESC
LIMIT 3

-- 144. «Клієнти з найстабільнішими чеками»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROund((SUM(unit_price * quantity * (1-discount))::numeric),2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id)
SELECT customer_id
       ,ROUND((STDDEV(sum_chek)::numeric),2) as std_dev_sum_chek
FROM level1
GROUP BY customer_id
ORDER BY std_dev_sum_chek
LIMIT 5

-- 145. Знайди постачальників, у яких середня ціна їхніх товарів суттєво вища за ринкову.

WITH level1 as(SELECT supplier_id
       ,company_name
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price_per_supplier
	   ,ROUND((SELECT avg(unit_price) FROM products)::numeric,2) as total_avg
FROM products
JOIN suppliers USING(supplier_id)
GROUP BY supplier_id,company_name)
SELECT *
FROM level1
WHERE avg_price_per_supplier > total_avg * 1.3

-- 146. «Знайди топ-5 товарів, які приносять найбільший виторг загалом»

SELECT product_id
       ,product_name
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM products p
JOIN order_details USING(product_id)
GROUP BY product_id,product_name
ORDER BY sum_chek DESC
LIMIT 5

-- 147. «Знайди місяць, у який було оформлено найбільше замовлень»

SELECT EXTRACT(month from order_date) as month
       ,EXTRACT(year from order_date) as year
       ,COUNT(*) as count_orders
FROM orders
GROUP BY EXTRACT(month from order_date), EXTRACT(year from order_date)
ORDER BY count_orders DESC
LIMIT 1

-- 148. «Для кожного клієнта знайди різницю між сумою його останнього замовлення і попереднього»

WITH level1 as(SELECT customer_id
       ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_date),
level2 as(SELECT customer_id
       ,order_date
       ,sum_chek
	   ,LAG(sum_chek) OVER(partition by customer_id order by order_date) as prev_chek
FROM level1),
level3 as(SELECT *
       ,MAX(order_date) OVER (partition by customer_id) as max_date
FROM level2),
level4 as(SELECT *
       ,sum_chek - prev_chek as diff
FROM level3
WHERE order_date = max_date)
SELECT *
FROM level4
WHERE diff > 0

-- 149. Пари товарів, які найчастіше купують разом

WITH level1 as(SELECT order_id
       ,product_id
FROM order_details 
JOIN products USING(product_id))
SELECT t1.product_id as prod_1
	   ,t2.product_id as prod_2
	   ,COUNT(distinct t1.order_id) as count_order
FROM level1 t1
JOIN level1 t2 On t1.order_id=t2.order_id AND t1.product_id < t2.product_id
GROUP BY t1.product_id, t2.product_id 
ORDER BY count_order DESC
LIMIT 10

-- 150. «Знайди товари, чия ціна входить у топ-10% найдорожчих товарів»

WITH level1 as(SELECT product_id
       ,product_name
	   ,unit_price
	   ,ROUND((SELECT percentile_cont(0.9) within group (order by unit_price) FROM products)::numeric,2) as perc_90
FROM products
GROUP BY product_id, product_name, unit_price)
SELECT *
FROM level1
WHERE unit_price >= perc_90

-- 151. «Знайди товари, у яких виявлено аномалію знижок: середня знижка на товар зростає,
-- а середня ціна після знижки теж зростає.»

WITH level1 as(SELECT product_id
       ,product_name
	   ,ROUND(AVG(discount)::numeric,4) as avg_discount
	   ,ROUND(AVG(p.unit_price * (1 - discount))::numeric,2) as avg_final_price
	   ,ROUND((SELECT AVG(discount) FROM order_details)::numeric,4) as global_avg_discount
	   ,ROUND((SELECT AVG(unit_price * (1-discount)) FROM order_details)::numeric,2) as global_final_price
FROM order_details 
JOIN products p USING(product_id)
GROUP BY product_id,product_name)
SELECT *
FROm level1
WHERE avg_discount > global_avg_discount AND avg_final_price > global_final_price

-- 152.«Для кожного клієнта нормалізуй суму замовлення за формулою:
-- order_sum / max_order_sum_for_this_customer
-- і виведи тільки ті замовлення, де нормалізована сума > 0.8»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id,order_id, order_date),
level2 as(SELECT *
       ,MAX(sum_chek) OVER (partition by customer_id) as max_sum_chek_per_customer
FROM level1),
level3 as(SELECT *
       ,ROUND((sum_chek::numeric / max_sum_chek_per_customer::numeric),2) as ratio
FROM level2)
SELECT *
FROM level3
WHERE ratio > 0.8 

-- 153. «Для кожного клієнта класифікуй кожне його замовлення як:
-- LARGE, якщо сума > 75-й перцентиль його власних замовлень
-- SMALL, якщо сума < 25-го перцентиля
-- MEDIUM у всіх інших випадках»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROm orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.25) within group (order by sum_chek) as perc_25
	   ,percentile_cont(0.75) within group (order by sum_chek) as perc_75
FROM level1
GROUP By customer_id),
level3 as(SELECT *
FROM level1 
JOIN level2 USING(customer_id))
SELECT *
       ,case when sum_chek > perc_75 THEN 'Large'
	   when sum_chek < perc_25 THEN 'small'
	   ELSE 'medium' END as order_type
FROm level3
ORDER BY customer_id, order_date

-- 154. «Для кожного клієнта визнач, чи повернувся він у наступному місяці
-- після свого першого замовлення.»

WITH level1 as(SELECT DISTINCT order_date
       ,customer_id
	   ,date_trunc('month', order_date) + interval '1 month' as next_date
FROm orders
ORDER BY customer_id, order_date),
level2 as(SELECT *
       ,EXTRACT(year FROM next_date) as next_year
	   ,EXTRACT(month FROM next_date) as next_month
	   ,EXTRACT(year FROm order_date) as prev_year
	   ,EXTRACT(month FROM order_date) as prev_month
FROm level1),
level3 as(SELECT *
       ,case when next_year=prev_year AND next_month=prev_month THEN 'yes' ELSE 'no' END as yes_no
	   ,ROW_number() OVER (partition by customer_id order by order_date) as rn
FROm level2)
SELECT *
FROM level3
WHERE rn = 1

SELECT DISTINCT order_date
       ,customer_id
	   ,date_trunc('month', order_date) + interval '1 month' as next_date
FROm orders
ORDER BY customer_id, order_date

-- нижче код чатіка

WITH first_order AS (
    SELECT
        customer_id,
        MIN(order_date) AS first_date,
        EXTRACT(YEAR  FROM MIN(order_date)) AS first_year,
        EXTRACT(MONTH FROM MIN(order_date)) AS first_month,
        EXTRACT(YEAR  FROM (MIN(order_date) + INTERVAL '1 month')) AS next_year,
        EXTRACT(MONTH FROM (MIN(order_date) + INTERVAL '1 month')) AS next_month
    FROM orders
    GROUP BY customer_id
)
SELECT
    f.customer_id,
    CASE WHEN COUNT(o2.order_id) > 0 THEN 1 ELSE 0 END AS returned_flag
FROM first_order f
JOIN orders o2
   ON o2.customer_id = f.customer_id
  AND EXTRACT(YEAR  FROM o2.order_date) = f.next_year
  AND EXTRACT(MONTH FROM o2.order_date) = f.next_month
GROUP BY f.customer_id
ORDER BY f.customer_id;