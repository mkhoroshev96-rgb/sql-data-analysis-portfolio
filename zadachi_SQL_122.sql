-- 827. «Фантомний максимум»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
	   ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
FROM level1),
level3 as(SELECT *
       ,case when prev_chek + next_chek > max_chek THEN 1 ELSE 0 END as flag_chek
FROm level2
WHERE sum_chek = max_chek)
SELECT *
FROM level3
WHERE flag_chek = 1

-- 828. «Невидимий перелом клієнта»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details using (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,array_agg(sum_chek) OVER (partition by customer_id order by order_date) as arr_left
	   ,array_agg(sum_chek) OVER (partition by customer_id order by order_date DESC) as arr_right
FROM level1
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,sum_chek
	   ,percentile_cont(0.5) WITHIN GROUP (order by val) as median_left
FROM level2
CROSS JOIN LATERAL unnest(arr_left) as val
GROUP By customer_id, order_id, order_date, sum_chek),
level4 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,percentile_cont(0.5) WITHIN GROUP (order by val) as median_right
FROM level2
CROSS JOIN LATERAL unnest(arr_right) as val
GROUP By customer_id, order_id, order_date, sum_chek),
level5 as(SELECT *
FROm level3
JOIN level4 USING (customer_id, order_id, order_date))
SELECT *
FROM level5
WHERE median_left > median_right
ORDER BY customer_id, order_date

-- 829. «Індекс фальшивої вірності товару»

WITH level1 as(SELECT customer_id
	   ,order_id
	   ,order_date
	   ,product_id
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,COUNT(product_id) OVER (partition by customer_id,product_id) as count_product_customer
FROM level1),
level3 as(SELECT DISTINCT customer_id
       ,product_id
	   ,count_product_customer
	   ,case when count_product_customer = 1 THEN 'one_buy'
	   else 'more_buy' END as gradation
FROm level2
ORDER BY customer_id),
level4 as(SELECT *
       ,COUNT(product_id) FILTER (WHERE gradation = 'one_buy') OVER (partition by product_id) as count_one_buy
	   ,COUNT(product_id) OVER (partition by product_id) as total_count
FROM level3),
level5 as(SELECT *
       ,ROUND((count_one_buy::numeric/total_count::numeric),4) as ratio
FROM level4)
SELECT DISTINCT product_id
       ,count_one_buy
	   ,total_count
	   ,ratio
FROM level5
ORDER BY ratio DESC

-- 830. «Індекс монополії клієнта»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,(unit_price * quantity * (1-discount)) as chek
FROM orders
JOIN order_details USING(order_id)),
level2 as(SELECT customer_id
       ,COUNT(DISTINCT product_id) as count_unik_product
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
FROM level1
JOIN level2 USING (customer_id)
WHERE count_unik_product >= 5),
level4 as(SELECT *
       ,SUM(chek) OVER (partition by customer_id, product_id) as sum_chek_product
	   ,SUM(chek) OVER (partition by customer_id) as total_revenue
FROm level3),
level5 as(SELECT DISTINCT customer_id
       ,product_id
	   ,sum_chek_product
	   ,total_revenue
	   ,count_unik_product
FROm level4
ORDER BY customer_id),
level6 as(SELECT *
       ,MAX(sum_chek_product) OVER (partition by customer_id) as max_chek_product
FROm level5),
level7 as(SELECT *
       ,max_chek_product / total_revenue as monopoly_index
FROM level6)
SELECT DISTINCT customer_id
       ,max_chek_product
	   ,total_revenue
	   ,count_unik_product
	   ,monopoly_index
FROm level7
WHERE monopoly_index > 0.5
ORDER BY monopoly_index DESC

-- 831. «Індекс ритмічності клієнта»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
FROM level1),
level3 as(SELECT *
       ,order_date - prev_date as interval
FROm level2
WHERE count_order >= 6 AND prev_date is not null),
level4 as(SELECT customer_id
       ,STDDEV(interval)  as stddev_interval
	   ,AVG(interval) as avg_interval
FROm level3
GROUP By customer_id)
SELECT *
       ,stddev_interval / avg_interval as rhythm_index
FROM level4
ORDER BY rhythm_index DESC

-- 832. «Тіньовий товар клієнта»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,(unit_price * quantity * (1-discount)) as chek
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,SUM(chek) OVER (partition by customer_id, order_id) as sum_order_chek
	   ,ROW_NUMBER () OVER (partition by customer_id, order_id order by chek DESC) as rn_order
	   ,COUNT(product_id) OVER (partition by customer_id, product_id) as count_product_order
FROM level1),
level3 as(SELECT *
       ,COUNT(order_id) FILTER (WHERE rn_order = 1) OVER (partition by customer_id, product_id) as product_top_in_order
FROM level2
WHERE count_product_order >= 2)
SELECT *
FROm level3
WHERE product_top_in_order = 0

-- 833. «Парадокс великої знижки»

WITH level1 as(SELECT product_id
       ,order_id
	   ,discount
	   ,quantity
	   ,COUNT(product_id) OVER (partition by product_id) as count_product
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,case when discount = 0 THEN 'not_discount'
	   else 'with_discount' END as gradation
FROm level1
WHERE count_product >= 10),
level3 as(SELECT product_id
       ,AVG(quantity) FILTER (WHERE gradation = 'not_discount') as avg_quantity_not_discount
	   ,AVG(quantity) FILTER (WHERE gradation = 'with_discount') as avg_quantity_with_discount
FROm level2
GROUP By product_id)
SELECT *
FROm level3
WHERE avg_quantity_with_discount > avg_quantity_not_discount