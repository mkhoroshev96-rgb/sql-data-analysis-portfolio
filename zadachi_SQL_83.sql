-- 529. «Клієнт з ефектом умовної раціональності»

with level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,case when sum_chek < median_chek THEN 'low_orders'
	   when sum_chek >= median_chek THEN 'high_orders'
	   END as gradation
FROm level1
JOIN level2 USING (customer_id)
WHERE count_order >= 8),
level4 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'low_orders')::numeric,2) as avg_chek_low
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'high_orders')::numeric,2) as avg_chek_high
	   ,ROUND(STDDEV(sum_chek) FILTER (WHERE gradation = 'low_orders')::numeric,2) as stddev_chek_low
	   ,ROUND(STDDEV(sum_chek) FILTER (WHERE gradation = 'high_orders')::numeric,2) as stddev_chek_high
FROm level3
GROUP By customer_id),
level5 as(SELECT *
       ,ROUND((stddev_chek_low / avg_chek_low)::numeric,4) as cv_low
	   ,ROUND((stddev_chek_high / avg_chek_high)::numeric,4) as cv_high
FROm level4)
SELECT *
FROM level5
WHERE cv_low >= 1.3 * cv_high AND avg_chek_high > avg_chek_low

-- 530. «Клієнт з ефектом зсуву норми»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,case when rn <= middle_point THEN 'before'
	   when rn > middle_point THEN 'after'
	   END as medians_group
FROM level1
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE medians_group = 'before')::numeric,2) as avg_chek_before
	   ,ROUND(AVG(sum_chek) FILTER (WHERE medians_group = 'after')::numeric,2) as avg_chek_after
	   ,ROUND(AVG(avg_chek) FILTER (WHERE medians_group = 'before')::numeric,2) as global_avg_chek
FROM level2
GROUP By customer_id),
level4 as(SELECT *
       ,ROUND(ABS((avg_chek_before - global_avg_chek) / global_avg_chek)::numeric,4) as diff_chek_before
	   ,ROUND(ABS((avg_chek_after - global_avg_chek) / global_avg_chek)::numeric,4) as diff_chek_after
	   ,ROUND(ABS((avg_chek_after - avg_chek_before) / avg_chek_before)::numeric,4) as diff_chek_before_after
FROM level3)
SELECT *
FROm level4
WHERE diff_chek_before <= 0.2 AND diff_chek_after <= 0.2 AND diff_chek_before_after >= 0.4

-- 531. «Клієнт з ефектом втраченої памʼяті»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,ABS(sum_chek - prev_chek) as abs_delta
       ,count_order - 1 as real_count_order
FROM level2
WHERE prev_chek is not null),
level4 as(SELECT *
       ,real_count_order / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM level3),
level5 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROM level4),
level6 as(SELECT customer_id
       ,ROUND(AVG(abs_delta) FILTER (WHERE halfs = 'first')::numeric,2) as avg_abs_delta_first
	   ,ROUND(AVG(abs_delta) FILTER (WHERE halfs = 'second')::numeric,2) as avg_abs_delta_second
FROM level5
GROUP BY customer_id)
SELECT *
FROM level6
WHERE avg_abs_delta_first < avg_abs_delta_second AND avg_abs_delta_second >= 2 * avg_abs_delta_first

-- 532. «Клієнт з ефектом інверсії очікування»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,case when sum_quantity < median_quantity THEN 'low'
	   when sum_quantity >= median_quantity THEN 'high'
	   END as quantitys_group
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 8),
level4 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE quantitys_group = 'low')::numeric,2) as avg_chek_low
	   ,ROUND(AVG(sum_chek) FILTER (WHERE quantitys_group = 'high')::numeric,2) as avg_chek_high
FROM level3
GROUP BY customer_id)
SELECT *
FROM level4
WHERE avg_chek_high <= avg_chek_low

-- 533. «Клієнт з ефектом фантомного тренду»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id order by order_date)::numeric,2) as running_avg_chek
	   ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,case when sum_chek > running_avg_chek THEN 1 ELSE 0 END as flag_chek
FROM level2),
level4 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROM level3),
level5 as(SELECT *
       ,ROUND((total_revenue - sum_chek) / (count_order - 1)::numeric,2) as avg_chek_ohne_order
FROM level4
WHERE sum_flag_chek >= 3),
level6 as(SELECT *
       ,case when sum_chek > avg_chek_ohne_order THEN 1 ELSE 0 END as flag_ohne_order
FROm level5),
level7 as(SELECT *
       ,SUM(flag_ohne_order) OVER (partition by customer_id) as sum_flag_ohne_order
FROm level6)
SELECT *
FROm level7
WHERE sum_flag_ohne_order = 0

-- 534. «Клієнт з ефектом неправильної узагальненості»

WITH block1 as(WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date)
SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as stddev_chek
FROm level1
WHERE count_order >= 5),
block2 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,unit_price
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,ROUND(STDDEV(unit_price) OVER (partition by customer_id, order_id)::numeric,2) as std_dev_price_order
FROM level1)
SELECT DISTINCT customer_id
       ,order_id
	   ,std_dev_price_order
FROm level2),
block3 as(SELECT *
       ,ROUND(avg(std_dev_price_order) OVER (partition by customer_id)::numeric,2) as avg_stddev_price_order
FROm block1
JOIn block2 USING (customer_id, order_id)
WHERE std_dev_price_order is not null),
block4 as(SELECT DISTINCT customer_id
	   ,stddev_chek
	   ,avg_stddev_price_order
	   ,ntile(4) OVER (order by stddev_chek DESC) as ntile_stddev_chek
	   ,ntile(4) OVER (order by avg_stddev_price_order DESC) as ntile_stddev_price
FROm block3)
SELECT *
FROm block4
WHERE ntile_stddev_price = 1 AND ntile_stddev_chek IN (2,3,4)

-- 535. «Клієнт з ефектом локальної логіки»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
FROM level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,ROUND(((prev_chek + next_chek) / 2)::numeric,2) as avg_prev_next
FROm level2
WHERE prev_chek is not null AND next_chek is not null),
level4 as(SELECT *
       ,ROUND(ABS((sum_chek - avg_prev_next) / avg_prev_next)::numeric,2) as diff_prev_next
FROm level3),
level5 as(SELECT *
       ,case when diff_prev_next <= 0.1 THEN 1 else 0 END as flag_diff
FROm level4),
level6 as(SELECT *
       ,SUM(flag_diff) OVER (partition by customer_id) as sum_flag_diff
FROm level5)
SELECT *
FROM level6
WHERE sum_flag_diff >= 3