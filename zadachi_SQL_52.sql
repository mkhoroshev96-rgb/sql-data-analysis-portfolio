-- 326. Знайти клієнтів, у яких “нерівна стабільність чеків”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
FROM level1
WHERE count_order >= 5),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
	   ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
FROM level2
GROUP BY customer_id),
level4 as(SELECT *
       ,ROUND((avg_chek / median_chek)::numeric,2) as ratio
FROM level3)
SELECT *
FROM level4
WHERE ratio >= 1.25 

-- 327. “Клієнти з розривом ритму”

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,order_date - prev_date as interval
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,MAX(interval)  as max_interval
	   ,percentile_cont(0.5) WITHIN GROUP (order by interval) as median_interval
FROM level2
GROUP By customer_id),
level4 as(SELECT *
       ,ROUND((max_interval::numeric / median_interval::numeric),2) as ratio_interval
FROM level2
JOIn level3 USING(customer_id)),
level5 as(SELECT *
       ,MAX(case when max_interval = interval THEN order_date END) OVER (partition by customer_id) as date_max_interval
FROM level4
WHERE ratio_interval >= 3),
level6 as(SELECT *
       ,case when order_date < date_max_interval THEN '1_before'
	   when order_date > date_max_interval THEN '2_after'
	   when order_date = date_max_interval THEN 'pause'
	   END as gradation
FROM level5),
level7 as(SELECT *
       ,COUNT(*) FILTER (where gradation = '1_before') OVER (partition by customer_id) as count_order_in_before
	   ,COUNT(*) FILTER (where gradation = '2_after') OVER (partition by customer_id) as count_order_in_after
FROM level6
WHERE gradation IN ('1_before','2_after')),
level8 as(SELECT *
       ,ROW_NUMBER() OVER (partition by customer_id,gradation order by order_date DESC) as rn_before
	   ,ROW_NUMBER() OVER (partition by customer_id,gradation order by order_date) as rn_after
FROm level7
WHERE count_order_in_before >= 2 AND count_order_in_after >= 2),
level9 as(SELECT *
FROM level8
WHERE (rn_before <= 2 AND gradation = '1_before') OR (rn_after <= 2 AND gradation = '2_after')),
level10 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = '1_before') OVER (partition by customer_id)::numeric,2) as avg_chek_before
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = '2_after') OVER (partition by customer_id)::numeric,2) as avg_chek_after
FROM level9)
SELECT *
FROM level10
WHERE avg_chek_after < avg_chek_before

-- 328. "Замовлення з ілюзією різноманіття"

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,ROUND((unit_price * quantity * (1-discount))::numeric,2) as chek
FROM orders
JOIN order_details USING(order_id)
ORDER BY customer_id, order_id),
level2 as(SELECT customer_id
       ,order_id
	   ,COUNT(DISTINCT product_id) as count_distinct_product
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROm orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id),
level3 as(SELECT *
       ,ROUND((chek / sum_chek)::numeric,2) as ratio
FROM level1
JOIN level2 USING(customer_id, order_id)
WHERE count_distinct_product >= 3),
level4 as(SELECT *
       ,MAX(ratio) OVER (partition by customer_id,order_id) as max_ratio
FROM level3)
SELECT *
FROM level4
WHERE max_ratio >= 0.7

-- 329. “Клієнти з парадоксом стабільності”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
	   ,MIN(sum_chek) OVER (partition by customer_id) as min_chek
FROM level1
WHERE count_order >= 5),
level3 as(SELECT *
       ,ROUND((max_chek / avg_chek)::numeric,2) as ratio_max
	   ,ROUND((min_chek / avg_chek)::numeric,2) as ratio_min
FROM level2)
SELECT *
FROm level3
WHERE ratio_max >= 1.5 AND ratio_min <= 0.5

-- 330. “Категорія-обманщик”

WITh level1 as(SELECT category_id
       ,customer_id
	   ,order_id
	   ,ROUND((p.unit_price * quantity * (1-discount))::numeric,2) as chek
FROm orders
JOIN order_details USING(order_id)
JOIn products p USING(product_id)
JOIN categories USING(category_id)
ORDER BY category_id, customer_id,order_id),
level2 as(SELECT category_id
       ,customer_id
	   ,SUM(chek) as sum_chek_per_customer_in_category
FROm level1
GROUP By category_id, customer_id),
level3 as(SELECT category_id
       ,COUNT(DISTINCT customer_id) as count_distinct_customer
FROM orders
JOIN order_details USING(order_id)
JOIN products USING(product_id)
JOIN categories USING(category_id)
GROUP By category_id),
level4 as(SELECT *
       ,SUM(sum_chek_per_customer_in_category) OVER (partition by category_id) as total_revenue_per_category
FROm level2
JOIN level3 USING(category_id)
WHERE count_distinct_customer >= 20),
level5 as(SELECT *
       ,ROUND(((sum_chek_per_customer_in_category / total_revenue_per_category)*100)::numeric,2) as ratio
FROm level4)
SELECT *
FROM level5
WHERE ratio > 20

-- 331. “Категорія з ілюзією популярності”

WITH level1 as(SELECT category_id
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as total_revenue
	   ,COUNT(DISTINCT order_id) as count_order
FROM orders
JOIN order_details USING(order_id)
JOIn products p USING(product_id)
JOIN categories USING(category_id)
GROUP BY category_id),
level2 as(SELECT *
       ,ROW_NUMBER () OVER (order by total_revenue DESC) as rank_revenue
	   ,ROW_NUMBER () OVER (order by count_order DESC) as rank_count_order
FROM level1),
level3 as(SELECT *
FROm level2
WHERE rank_revenue <= 3 AND rank_count_order <= 3)
SELECT *
FROM level3
WHERE rank_revenue <> rank_count_order

-- 332. “Замовлення з внутрішнім конфліктом ціни”

WITH level1 as (SELECT customer_id
       ,order_id
	   ,product_id
	   ,p.unit_price
FROm orders
JOIN order_details USING (order_id)
JOIN products p USING(product_id)),
level2 as(SELECT *
       ,ROUND(AVG(unit_price) OVER (partition by customer_id, order_id)::numeric,2) as avg_price
	   ,MAX(unit_price) OVER (partition by customer_id, order_id) as max_price
	   ,MIN(unit_price) OVER (partition by customer_id, order_id) as min_price
	   ,ROUND(AVG(unit_price) OVER ()::numeric,2) as global_avg_price
FROm level1),
level3 as(SELECT customer_id
       ,order_id
	   ,COUNT(DISTINCT product_id) as count_distinct_prod
FROM orders
JOIN order_details USING(order_id)
JOIN products USING(product_id)
JOIN categories USING(category_id)
GROUP By customer_id, order_id),
level4 as(SELECT *
       ,ROUND((max_price / min_price)::numeric,2) as ratio
FROm level2
JOIN level3 USING(customer_id, order_id)
WHERE count_distinct_prod >= 3 AND avg_price > global_avg_price)
SELECT *
FROm level4
WHERE ratio >= 2.5

-- 333. “Замовлення з ілюзією вигідної знижки”

WITh level1 as(SELECT customer_id
       ,order_id
	   ,discount
	   ,unit_price
	   ,ROUND((unit_price * quantity * (1-discount))::numeric,2) as chek
FROM orders
JOIN order_details USING(order_id)),
level2 as(SELECT *
       ,ROUND(AVG(discount) OVER (partition by customer_id, order_id)::numeric,2) as avg_discount_order
	   ,ROUND(AVG(unit_price) OVER (partition by customer_id, order_id)::numeric,2) as avg_price_order
	   ,ROUND(AVG(unit_price) OVER ()::numeric,2) as global_avg_price
	   ,SUM(chek) OVER (partition by customer_id,order_id) as sum_chek
	   ,ROUND(AVG(chek) OVER ()::numeric,2) as global_avg_chek
FROm level1)
SELECT *
FROM level2
WHERE avg_discount_order >= 0.2 and avg_price_order >= global_avg_price AND sum_chek >= global_avg_chek 
