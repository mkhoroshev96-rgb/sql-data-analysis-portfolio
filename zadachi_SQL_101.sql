-- 654. Реверсивна кумулятивна асиметрія

WITH level1 as(SELECt customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
	   ,SUM(sum_chek) OVER (partition by customer_id order by order_date) as cumm_sum_chek
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
	   ,SUM(sum_chek) OVER (partition by customer_id order by order_date DESC) as cumm_sum_chek_invert
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_invert
FROm level1
WHERE count_order >= 9),
level3 as(SELECT *
       ,ROUND((cumm_sum_chek / total_revenue)::numeric,4) as ratio
	   ,ROUND((cumm_sum_chek_invert / total_revenue)::numeric,4) as ratio_invert
	   ,ROUND((rn::numeric / count_order::numeric),4) as ratio_rn
	   ,ROUND((rn_invert::numeric / count_order::numeric),4) as ratio_rn_invert
FROm level2),
level4 as(SELECT customer_id
       ,count_order
	   ,rn
	   ,ratio
	   ,ratio_rn
FROM level3
WHERE ratio >= 0.8 AND ratio_rn >= 0.7),
level5 as(SELECT customer_id
       ,count_order
	   ,rn_invert
	   ,ratio_invert
	   ,ratio_rn_invert
FROm level3
WHERE ratio_invert >= 0.8 AND ratio_rn_invert <= 0.4)
SELECT *
FROM level4 
JOIN level5 USING (customer_id)

-- 655. Локальна деградація при глобальному зростанні (Simpson-пастка)

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,category_id
	   ,p.product_id
	   ,ROUND((p.unit_price * quantity * (1-discount))::numeric,2) as chek
FROm orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)),
level2 as(SELECT customer_id
       ,order_id
       ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,count(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders),
level3 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROM level1
JOIN level2 USING (customer_id, order_id)
WHERE count_order >= 12),
level4 as(SELECT customer_id
       ,category_id
	   ,halfs
	   ,AVG(chek) as avg_chek_category
	   ,SUM(chek) as sum_chek_category
FROM level3
GROUP By customer_id, category_id, halfs),
level5 as(SELECT customer_id
       ,category_id
	   ,ROUND(AVG(avg_chek_category) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_category_first
	   ,ROUND(AVG(avg_chek_category) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_category_second
	   ,SUM(sum_chek_category) FILTER (WHERE halfs = 'first') as sum_chek_category_first
	   ,SUM(sum_chek_category) FILTER (WHERE halfs = 'second') as sum_chek_category_second
FROM level4
GROUP By customer_id, category_id),
level6 as(SELECT *
       ,ROUND(AVG(sum_chek_category_first) OVER (partition by customer_id)::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek_category_second) OVER (partition by customer_id)::numeric,2) as avg_chek_second
FROm level5),
level7 as(SELECT customer_id
       ,category_id
	   ,avg_chek_category_first
	   ,avg_chek_category_second
	   ,case when avg_chek_category_second < avg_chek_category_first THEN 1 ELSE 0 END as flag_avg
	   ,COUNT(category_id) OVER (partition by customer_id) as count_category
FROm level6
WHERE avg_chek_second > avg_chek_first),
level8 as(sELECT *
       ,SUM(flag_avg) OVER (partition by customer_id) as sum_flag_avg
FROM level7)
SELECT *
FROm level8
WHERE count_category = sum_flag_avg

-- 656. «Клієнт з ефектом прихованого зсуву маржинальності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,AVG(discount) as avg_discount
	   ,Sum(unit_price * quantity * (1-discount) - (0.7 * unit_price) * quantity) as profit
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,profit / sum_quantity as profit_per_unit
	   ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROm level1
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,ROUND(AVG(avg_discount) FILTER (WHERE halfs = 'first')::numeric,4) as avg_discount_first
	   ,ROUND(AVG(avg_discount) FILTER (WHERE halfs = 'second')::numeric,4) as avg_discount_second
	   ,ROUND(AVG(profit_per_unit) FILTER (WHERE halfs = 'first')::numeric,4) as avg_profit_first
	   ,ROUND(AVG(profit_per_unit) FILTER (WHERE halfs = 'second')::numeric,4) as avg_profit_second
FROm level2
GROUP By customer_id)
SELECT *
FROm level3
WHERE avg_discount_second > avg_discount_first AND avg_profit_second > avg_profit_first

-- 657. «Клієнт із ефектом локальної маржинальної нестабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount) - (0.7 * unit_price) * quantity)::numeric,2) as profit
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND((profit / sum_quantity)::numeric,4) as profit_per_unit
FROm level1
WHERE count_order >= 8),
level3 as(SELECT * 
       ,ROUND(STDDEV(profit_per_unit) OVER (partition by customer_id)::numeric,4) as stddev_chek
	   ,ROUND(AVG(profit_per_unit) OVER (partition by customer_id)::numeric,4) as avg_chek
FROm level2)
SELECT *
FROm level3
WHERE stddev_chek < 0.15 * avg_chek

-- 658. «Клієнт із ефектом асиметричної маржі»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount) - (0.7*unit_price) * quantity)::numeric,2) as profit
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND((profit / sum_quantity)::numeric,4) as profit_per_unit
FROm level1
WHERE count_order >= 9),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by profit_per_unit) as median_profit
	   ,ROUND(AVG(profit_per_unit)::numeric,4) as avg_profit
FROM level2
GROUP By customer_id),
level4 as(SELECT *
       ,MAX(profit_per_unit) OVER (partition by customer_id) as max_profit
FROm level2
JOIN level3 USING (customer_id)
WHERE median_profit < 0.8 * avg_profit)
SELECT *
FROm level4
WHERE max_profit > 3 * median_profit

-- 659. «Клієнт із ефектом маржинального канібалізму»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount) - (0.7*unit_price) * quantity)::numeric,4) as profit
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND((profit / sum_quantity)::numeric,4) as profit_per_unit
FROM level1
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,ROUND(corr(sum_quantity, profit_per_unit)::numeric,4) as corr_qnt_profit
FROM level2
GROUP BY customer_id)
SELECT *
FROm level3
WHERE corr_qnt_profit < - 0.4

-- 660. «Клієнт із ефектом нестабільного чека»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT *
       ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as stddev_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROM level1
WHERE count_order >= 9),
level3 as(SELECT *
       ,case when sum_chek > 2 * avg_chek THEN 1 ELSE 0 END as flag_chek
FROm level2
WHERE stddev_chek < 0.25 * avg_chek),
level4 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROm level3)
SELECT *
FROM level4
WHERE sum_flag_chek >= 2

-- 661. «Клієнт із ефектом цінового дрейфу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) / sum(quantity) as price
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT *
       ,AVG(sum_quantity) OVER (partition by customer_id) as avg_quantity
	   ,STDDEV(sum_quantity) OVER (partition by customer_id) as stddev_quantity
FROm level1
WHERE count_order >= 10),
level3 as(SELECT *
FROm level2
WHERE stddev_quantity < 0.1 * avg_quantity),
level4 as(SELECT customer_id
       ,ROUND(corr(rn, price)::numeric,4) as corr_rn_price
FROM level3
GROUP By customer_id)
SELECT *
FROm level4
WHERE corr_rn_price > 0.4