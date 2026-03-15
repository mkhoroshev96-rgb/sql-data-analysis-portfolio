-- 695. «Клієнт з ефектом згладженого піку»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as stddev_chek
FROM level1
WHERE count_order >= 12),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROm level2
GROUP BY customer_id),
level4 as(SELECT *
       ,ROUND((max_chek / median_chek)::numeric,4) as diff_max_median
	   ,ROUND((stddev_chek / avg_chek)::numeric,4) as cv
FROm level2
JOIN level3 USING (customer_id))
SELECT *
FROm level4
WHERE diff_max_median > 2 AND cv < 0.4

-- 696. «Клієнт з ефектом незмінного середнього при зміні структури»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROM level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,case when sum_chek > avg_chek THEN 'high_avg'
	   when sum_chek < avg_chek THEN 'low_avg'
	   when sum_chek = avg_chek THEN 'equal_avg'
	   END as gradation
FROm level2),
level4 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first' AND gradation = 'high_avg')::numeric,2) as avg_chek_high_avg_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second' AND gradation = 'high_avg')::numeric,2) as avg_chek_high_avg_second
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
FROm level3
GROUP BY customer_id),
level5 as(SELECT *
       ,ROUND(ABS((avg_chek_high_avg_second - avg_chek_high_avg_first) / avg_chek_high_avg_first)::numeric,4) as diff_chek_high_avg
	   ,ROUND(ABS((avg_chek_second - avg_chek_first) / avg_chek_first)::numeric,4) as diff_chek_halfs
FROM level4)
SELECT *
FROM level5
WHERE diff_chek_halfs <= 0.03 AND diff_chek_high_avg >= 0.25

-- 697. «Клієнт з ефектом інверсії рангу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ntile(3) OVER (partition by customer_id order by order_date) as ntile_date
	   ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROm level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,MAX(case when sum_chek = max_chek THEN ntile_date END) OVER (partition by customer_id) as ntile_max_chek
FROm level2),
level4 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE ntile_date = 3) OVER (partition by customer_id)::numeric,2) as avg_chek_ntile_3
FROm level3
WHERE ntile_max_chek = 1)
SELECT *
FROm level4
WHERE avg_chek_ntile_3 > avg_chek

-- 698. «Клієнт з ефектом прихованої концентрації»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
FROM level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,ROUND((sum_chek / total_revenue)::numeric,4) as ratio_chek
FROM level2),
level4 as(SELECT *
       ,case when ratio_chek <= 0.4 THEN 0 ELSE 1 END as flag_ratio_chek
	   ,row_number () OVER (partition by customer_id order by ratio_chek DESC) as rn_ratio
FROm level3),
level5 as(SELECT *
       ,SUM(flag_ratio_chek) OVER (partition by customer_id) as sum_flag_ratio_chek
FROm level4
WHERE rn_ratio <= 2),
level6 as(SELECT *
       ,Sum(ratio_chek) FILTER (WHERE rn_ratio <= 2) OVER (partition by customer_id) as sum_ratio_top_2
FROm level5
WHERE sum_flag_ratio_chek = 0)
SELECT *
FROM level6
WHERE sum_ratio_top_2 > 0.6

-- 699. «Клієнт з ефектом стабільного зростання без зростання»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_last
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(sum_chek) FILTER (WHERE rn_last <= 3) OVER (partition by customer_id)::numeric,2) as avg_chek_last_3
FROm level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
FROm level2
WHERE avg_chek_last_3 < avg_chek),
level4 as(SELECT *
       ,case when next_chek >= sum_chek THEN 1 ELSE 0 END as flag_chek
FROM level3
WHERE next_chek is not null),
level5 as(SELECT *
       ,count_order - 1 as real_count
	   ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROM level4)
SELECT *
FROm level5
WHERE real_count = sum_flag_chek

-- 700. «Клієнт з ефектом інваріантного середнього при повній інверсії структури»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(sum(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROm level1
WHERE count_order >= 12),
level3 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROm level2
GROUP BY customer_id, halfs),
level4 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first') OVER (partition by customer_id)::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second') OVER (partition by customer_id)::numeric,2) as avg_chek_second
	   ,ROUND(AVG(median_chek) FILTER (WHERE halfs = 'first') OVER (partition by customer_id)::numeric,2) as median_first
FROM level2
JOIN level3 USING (customer_id, halfs)),
level5 as(SELECT *
       ,ROUND(ABS((avg_chek_second - avg_chek_first) / avg_chek_first)::numeric,4) as diff_chek
FROm level4),
level6 as(SELECT *
       ,COUNT(order_id) FILTER (WHERE halfs = 'second') OVER (partition by customer_id) as count_order_second
	   ,case when sum_chek > median_first THEN 1 ELSE 0 END as flag_chek_and_median
FROm level5
WHERE diff_chek <= 0.02 AND halfs = 'second'),
level7 as(SELECT *
       ,SUM(flag_chek_and_median) OVER (partition by customer_id) as sum_flag_chek_and_median
FROm level6)
SELECT *
FROm level7
WHERE count_order_second = sum_flag_chek_and_median

-- 701. «Клієнт з ефектом інваріантного середнього при повному перевертанні порядку»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROM level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,max_chek - sum_chek as new_sum_chek
FROM level2),
level4 as(SELECT *
       ,ROUND(AVG(new_sum_chek) OVER (partition by customer_id)::numeric,2) as avg_new_sum_chek
FROM level3),
level5 as(SELECT *
       ,ROUND(ABS((avg_new_sum_chek - avg_chek) / avg_chek)::numeric,4) as diff_chek
FROM level4)
SELECT *
FROm level5
WHERE diff_chek <= 0.01

-- 702. «Клієнт з ефектом центру ваги»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROm level1
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,ROUND((sum(sum_chek * rn)) / (sum(rn))::numeric,2) as avg_whited_chek
FROm level2
GROUP BY customer_id),
level4 as(SELECT *
       ,ROUND(ABS((avg_whited_chek - avg_chek) / avg_chek)::numeric,4) as diff_chek
FROm level2
JOIN level3 USING (customer_id))
SELECT *
FROM level4
WHERE diff_chek <= 0.02

-- 703. «Клієнт з ефектом дзеркальної компенсації»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROm level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,ABS(sum_chek - avg_chek) as new_chek
	   ,ROUND((avg_chek / 2)::numeric,2) as half_avg_chek
FROm level2),
level4 as(SELECT *
       ,ROUND(AVG(new_chek) OVER (partition by customer_id)::numeric,2) as avg_new_chek
FROm level3),
level5 as(SELECT *
       ,ROUND(ABS((avg_new_chek - half_avg_chek) / half_avg_chek)::numeric,4) as diff_chek
FROm level4)
SELECT *
FROm level5
WHERE diff_chek <= 0.02

-- 704. «Клієнт з нульовим нахилом квадратичної маси»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,sum_chek * sum_chek as sum_chek_sqrt
	   ,AVG(sum_chek) OVER (partition by customer_id) as avg_chek
FROM level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,AVG(sum_chek_sqrt) OVER (partition by customer_id) as avg_chek_sqrt
	   ,avg_chek * avg_chek as sqrt_avg_chek
FROm level2),
level4 as(SELECT *
       ,ROUND(ABS((avg_chek_sqrt - sqrt_avg_chek) / sqrt_avg_chek)::numeric,4) as diff_chek
FROm level3)
SELECT *
FROm level4
WHERE diff_chek <= 0.02