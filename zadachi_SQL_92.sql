-- 597. «Клієнт з ефектом внутрішнього канібалізму»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,quantity 
	   ,ROUND((unit_price * quantity * (1-discount))::numeric,2) as chek
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,ROUND((chek / quantity)::numeric,2) as price_in_order
FROm level1),
level3 as(SELECT *
       ,ROUND(AVG(price_in_order) OVER (partition by customer_id, order_id)::numeric,2) as avg_price
	   ,MAX(price_in_order) OVER (partition by customer_id, order_id) as max_price
	   ,SUM(chek) OVER (partition by customer_id, order_id) as sum_chek
FROM level2),
level4 as(SELECT *
       ,ROUND((max_price / avg_price)::numeric,4) as price_spread
FROm level3),
level5 as(SELECT DISTINCT customer_id
       ,avg_price
	   ,max_price
	   ,price_spread
	   ,SUM(chek) OVER (partition by customer_id, order_id) as sum_chek
FROm level4),
level6 as(SELECT *
       ,ROUND(AVG(price_spread) OVER (partition by customer_id)::numeric,2) as avg_price_spread
	   ,ROUND(STDDEV(price_spread) OVER (partition by customer_id)::numeric,2) as stddev_price_spread
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROm level5),
level7 as(SELECT DISTINCT customer_id
       ,avg_price_spread
	   ,stddev_price_spread
	   ,avg_chek
FROm level6),
level8 as(SELECT *
       ,(SELECT percentile_cont (0.5) WITHIN GROUP (order by avg_chek) FROM level7) as global_median_avg_chek
FROm level7)
SELECT *
FROm level8
WHERE avg_chek >= global_median_avg_chek AND avg_price_spread >= 1.8 AND stddev_price_spread <= 0.4

-- 598. «Клієнт із втратою чутливості до обсягу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROM level1
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,halfs
	   ,ROUND(corr(sum_quantity, sum_chek)::numeric,4) as corr_qnt_chek
FROM level2
GROUP By customer_id, halfs),
level4 as(SELECT customer_id
       ,ROUND(AVG(corr_qnt_chek) FILTER (WHERE halfs = 'first')::numeric,4) as corr_qnt_chek_first
	   ,ROUND(AVG(corr_qnt_chek) FILTER (WHERE halfs = 'second')::numeric,4) as corr_qnt_chek_second
FROm level2
JOIN level3 USING (customer_id, halfs)
GROUP BY customer_id)
SELECT *
FROm level4
WHERE corr_qnt_chek_first >= 0.6 
AND corr_qnt_chek_second BETWEEN 0 AND 0.2

-- 599. «Клієнт з інверсією вигідності доставки»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,ROUND(AVG(freight)::numeric,2) as freight_customer
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND((freight_customer / sum_chek)::numeric,4) as shipping_ratio
	   ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROm level1
WHERE count_order >= 8),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
	   ,ROUND(AVG(shipping_ratio) FILTER (WHERE halfs = 'first')::numeric,4) as avg_shipping_first
	   ,ROUND(AVG(shipping_ratio) FILTER (WHERE halfs = 'second')::numeric,4) as avg_shipping_second
FROM level2
GROUP BY customer_id)
SELECT *
FROM level3
WHERE avg_shipping_second > avg_shipping_first AND avg_chek_second <= avg_chek_first

-- 600. «Клієнт із розірваною памʼяттю знижки»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(AVG(discount)::numeric,4) as avg_discount
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(avg_discount) OVER (partition by customer_id order by order_date) as prev_discount
	   ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROM level1
WHERE count_order >= 9),
level3 as(SELECT customer_id
       ,halfs
	   ,corr(prev_discount, sum_quantity) as corr_prev_disc_qnt
FROm level2
GROUP BY customer_id, halfs),
level4 as(SELECT customer_id
       ,ROUND(AVG(corr_prev_disc_qnt) FILTER (WHERE halfs = 'first')::numeric,4) as corr_prev_disc_qnt_first
	   ,ROUND(AVG(corr_prev_disc_qnt) FILTER (WHERE halfs = 'second')::numeric,4) as corr_prev_disc_qnt_second
FROM level2
JOIN level3 USING (customer_id, halfs)
GROUP BY customer_id)
SELECT *
FROm level4
WHERE corr_prev_disc_qnt_first >= 0.6 AND corr_prev_disc_qnt_second <= 0

-- 601. «Клієнт із ефектом знецінення повтору»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROm level1
GROUP BY customer_id),
level3 as(SELECT *
       ,case when sum_quantity >= median_quantity THEN 'high'
	   when sum_quantity < median_quantity THEN 'low'
	   END as volume
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 8),
level4 as(SELECT *
       ,LEAD(volume) OVER (partition by customer_id order by order_date) as next_volume
FROm level3),
level5 as(SELECT *
       ,case when volume = next_volume THEN 0 ELSE 1 END as flag_volume
FROm level4
WHERE next_volume is not null),
level6 as(SELECT *
       ,SUM(flag_volume) OVER (partition by customer_id order by order_date) as series_id
FROm level5),
level7 as(SELECT customer_id
       ,series_id
	   ,COUNT(series_id) as lange_series
FROm level6
GROUP BY customer_id, series_id),
level8 as(SELECT *
       ,LEAD(avg_price) OVER (partition by customer_id, series_id order by order_date) as next_price
FROm level6
JOIN level7 USING (customer_id, series_id)
WHERE lange_series >= 3),
level9 as(SELECT *
       ,case when avg_price > next_price THEN 1 ELSE 0 END as fall_price
FROm level8
WHERE next_price is not null),
level10 as(SELECT *
       ,SUM(fall_price) OVER (partition by customer_id, series_id) as sum_fall_price
	   ,COUNT(order_id) OVER (partition by customer_id, series_id) as real_lange_series
FROm level9)
SELECT *
FROm level10
WHERE sum_fall_price = real_lange_series

-- 602. «Клієнт з ефектом першого разу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,category_id
FROM orders
JOIN order_details USING (order_id)
JOIN products USING (product_id)
JOIN categories USING (category_id))
SELECT customer_id
       ,MIN(order_date) FILTER (WHERE category_id = 1) as first_date_1
	   ,MIN(order_date) FILTER (WHERE category_id = 2) as first_date_2
	   ,MIN(order_date) FILTER (WHERE category_id = 3) as first_date_3
	   ,MIN(order_date) FILTER (WHERE category_id = 4) as first_date_4
	   ,MIN(order_date) FILTER (WHERE category_id = 5) as first_date_5
	   ,MIN(order_date) FILTER (WHERE category_id = 6) as first_date_6
	   ,MIN(order_date) FILTER (WHERE category_id = 7) as first_date_7
	   ,MIN(order_date) FILTER (WHERE category_id = 8) as first_date_8
FROM level1
GROUP BY customer_id