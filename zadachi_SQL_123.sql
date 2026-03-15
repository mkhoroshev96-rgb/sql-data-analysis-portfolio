-- 834. «Зламаний порядок покупок»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,AVG(unit_price) as avg_price
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(avg_price) OVER (partition by customer_id order by order_date) as prev_price
	   ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,case when avg_price < prev_price AND sum_quantity >= prev_quantity * 3 THEN 1
	   ELSE 0 END as flag_price_quantity
FROM level2
WHERE prev_price is not null)
SELECT *
FROM level3
WHERE flag_price_quantity = 1

-- 835. «Парадокс популярного товару»

WITH level1 as(SELECT product_id
       ,order_id
	   ,(unit_price * quantity * (1-discount)) as chek
FROM orders
Join order_details USING (order_id)),
level2 as(SELECT product_id
       ,COUNT(DISTINCT order_id) as count_unik_order 
FROM level1
GROUP BY product_id),
level3 as(SELECT *
       ,SUM(chek) OVER (partition by product_id) as total_chek_product
FROM level1
JOIN level2 USING (product_id)
WHERE count_unik_order >= 20)
SELECT DISTINCT product_id
       ,count_unik_order
	   ,total_chek_product
FROM level3
ORDER BY total_chek_product

-- 836. «Парадокс дорогого замовлення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,AVG(unit_price) as avg_price
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,AVG(avg_price) OVER () as global_avg_price
	   ,AVG(sum_chek) OVER () as global_avg_chek
FROM level1)
SELECT *
FROM level2
WHERE avg_price > global_avg_price AND sum_chek < global_avg_chek

-- 837. «Серія стискання покупок»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
FROM level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,case when sum_chek > prev_chek AND sum_quantity < prev_quantity THEN 0
	   ELSE 1 END as flag_chek_quantity
FROM level2
WHERE prev_chek is not null),
level4 as(SELECT *
       ,SUM(flag_chek_quantity) OVER (partition by customer_id order by order_date) as series_id
FROM level3),
level5 as(SELECT customer_id
       ,series_id
	   ,COUNT(series_id) FILTER (WHERE flag_chek_quantity = 0) as length_series
FROM level4
GROUP By customer_id, series_id)
SELECT *
FROM level4
JOIN level5 USING (customer_id, series_id)
WHERE length_series >= 3

-- 838. «Ефект зламаного тренду»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
FROM level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,case when sum_chek > prev_chek THEN 0 ELSE 1 END as flag_chek
FROM level2
WHERE prev_chek is not null AND next_chek is not null),
level4 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id order by order_date) as series_id
FROM level3),
level5 as(SELECT customer_id
       ,series_id
	   ,COUNT(series_id) FILTER (WHERE flag_chek = 0) as length_series
FROm level4
GROUP BY customer_id, series_id),
level6 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id,series_id order by order_date DESC, order_id DESC) as rn_invert
FROm level4
JOIN level5 USING (customer_id, series_id)
WHERE length_series >= 4 AND flag_chek = 0),
level7 as(SELECT *
       ,case when next_chek < sum_chek * 0.3 AND rn_invert = 1 THEN 'yes'
	   Else 'no' END as yes_or_no
FROm level6)
SELECT *
FROm level7

-- 839. «Замовлення-маска»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,unit_price
	   ,(unit_price * quantity * (1-discount)) as chek
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,SUM(chek) OVER (partition by customer_id, order_id) as sum_chek_order
	   ,MAX(chek) OVER (partition by customer_id, order_id) as max_chek_order
	   ,AVG(unit_price) OVER () as global_avg_price_item
FROm level1),
level3 as(SELECT *
       ,max_chek_order/sum_chek_order as ratio
FROM level2)
SELECT *
FROM level3
WHERE ratio < 0.3 AND unit_price > global_avg_price_item

-- 840. «Перевернута знижка»

WITh level1 as(SELECT product_id
       ,order_id
	   ,unit_price
	   ,(unit_price * (1-discount)) as real_price
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT product_id
       ,AVG(unit_price) as avg_base_price
	   ,AVG(real_price) as avg_real_price
FROm level1
GROUP BY product_id)
SELECT *
FROm level2
WHERE avg_real_price > avg_base_price

-- 841. «Ефект зниклого товару»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders),
level3 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROm level1
JOIN level2 USING (customer_id, order_id, order_date)),
level4 as(SELECT product_id
	   ,COUNT(product_id) FILTER (WHERE halfs = 'first') as count_product_first
	   ,COUNT(product_id) FILTER (WHERE halfs = 'second') as count_product_second
FROM level3
GROUP BY product_id)
SELECT *
FROm level4
WHERE count_product_first >= 10 AND count_product_second = 0

-- 842. «Раптовий перелом тренду»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC, order_id DESC) as rn_invert
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id,order_date),
level2 as(SELECT *
       ,array_agg(sum_chek) OVER (partition by customer_id order by order_date, order_id) as arr
FROm level1
WHERE count_order >= 10 and rn_invert <= 5),
level3 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,sum_chek
	   ,percentile_cont(0.5) WITHIN GROUP (order by val) as mouving_median
FROM level2
CROSS JOIN LATERAL unnest(arr) as val
GROUP By customer_id, order_id, order_date, sum_chek)
SELECT *
FROm level3
WHERE sum_chek > mouving_median * 3